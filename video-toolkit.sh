#!/bin/bash
# ============================================================
# 录屏处理工具 — 一键从录屏到成片
# ============================================================
# 自动启用 .venv
if [ -z "$VIRTUAL_ENV" ] && [ -f "$(dirname "$0")/.venv/bin/activate" ]; then
  source "$(dirname "$0")/.venv/bin/activate"
fi
# 约定文件名（每个 feature 目录下）:
#   recording.mov   原始录屏（你录制的）
#   subtitles.srt   字幕（自动生成或手写）
#   ai_dub.wav      AI 配音
#   final.mp4       最终成片
#
# 用法:
#   ./video-toolkit.sh all    feature-05-cli-offline-config    全流程
#   ./video-toolkit.sh srt    feature-05-cli-offline-config    仅提取字幕
#   ./video-toolkit.sh dub    feature-05-cli-offline-config    仅生成AI配音+合成
#   ./video-toolkit.sh status feature-05-cli-offline-config    查看状态
#   ./video-toolkit.sh status --all                           查看全部 feature 状态
# ============================================================
set -e

BASE="$(cd "$(dirname "$0")/.." && pwd)"  # 默认搜索上级目录的 feature-*
TOOLKIT="$(cd "$(dirname "$0")" && pwd)"
VOICE="zh-CN-XiaoxiaoNeural"    # 微软神经语音（最自然）
VOICE_EN="en-US-AvaNeural"        # 美式英文，清晰亲和
EDGE_TTS="$TOOLKIT/.venv/bin/edge-tts"  # edge-tts 路径
ASR_ENGINE="${VIDEO_ASR:-faster-whisper}"   # faster-whisper | openai-whisper | funasr
DEEPSEEK_KEY="${DEEPSEEK_API_KEY:-}"   # 优先环境变量
# 其次从 ~/.aas_deepseek_key 读取（仅本机）
[ -z "$DEEPSEEK_KEY" ] && [ -f "$HOME/.aas_deepseek_key" ] && DEEPSEEK_KEY=$(cat "$HOME/.aas_deepseek_key" 2>/dev/null)

# ==================== 颜色 ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅${NC} $1"; }
warn() { echo -e "${YELLOW}⚠️${NC} $1"; }
err()  { echo -e "${RED}❌${NC} $1"; }
info() { echo -e "${CYAN}➜${NC} $1"; }

# 旋转等待动画
spinner() {
  local pid=$1 msg="${2:-处理中...}"
  local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    local c=${spin:$((i % 8)):1}
    echo -ne "\r  ${c} ${msg} ${i}s"
    sleep 1
    ((i++))
  done
  wait "$pid" 2>/dev/null
  local rc=$?
  echo -ne "\r                      \r"
  return $rc
}

# ==================== 依赖检查 ====================
check_env() {
    local missing=""
    command -v ffmpeg &>/dev/null || missing="ffmpeg $missing"
    python3 -c "from faster_whisper import WhisperModel" 2>/dev/null || \
    python3 -c "import whisper" 2>/dev/null || missing="whisper $missing"
    if [ -n "$missing" ]; then
        err "缺少: $missing"
        echo "  安装: brew install ffmpeg && pip3 install faster-whisper"
        return 1
    fi
    ok "环境就绪 (ffmpeg + whisper)"
}

# ==================== 解析 feature 目录 ====================
resolve_dir() {
    local name="$1"
    # 支持: feature-05-cli-offline-config 或 feature-05 或完整路径
    if [ -d "$name" ]; then
        echo "$(cd "$name" && pwd)"
    elif [ -d "$BASE/$name" ]; then
        echo "$BASE/$name"
    else
        # 模糊匹配
        local match=$(ls -d "$BASE"/feature-"${name#feature-}"* 2>/dev/null | head -1)
        [ -n "$match" ] && echo "$match" || echo ""
    fi
}

# ==================== 状态检查 ====================
show_status() {
    local dir="$1"
    local name=$(basename "$dir")
    
    echo ""
    echo "━━━ $name ━━━"
    
    local rec="$dir/recording.mov"
    local srt="$dir/subtitles.srt"
    local dub="$dir/ai_dub.wav"
    local out="$dir/final.mp4"
    
    local en_srt="$dir/subtitles_en.srt"
    local en_dub="$dir/ai_dub_en.wav"
    local en_out="$dir/final_en.mp4"
    
    [ -f "$rec" ]   && ok "recording.mov   ($(du -h "$rec" | cut -f1))"    || warn "recording.mov   缺失"
    [ -f "$srt" ]   && ok "subtitles.srt   ($(grep -c '^[0-9]' "$srt" 2>/dev/null || echo 0) 条)"  || warn "subtitles.srt   缺失"
    [ -f "$dub" ]   && ok "ai_dub.wav      ($(du -h "$dub" | cut -f1))"     || warn "ai_dub.wav      缺失"
    [ -f "$out" ]   && ok "final.mp4       ($(du -h "$out" | cut -f1))"     || warn "final.mp4       缺失"
    [ -f "$en_srt" ] && ok "subtitles_en.srt ($(grep -c '^[0-9]' "$en_srt" 2>/dev/null || echo 0) 条)" || true
    [ -f "$en_out" ] && ok "final_en.mp4    ($(du -h "$en_out" | cut -f1))"  || true
}

# ==================== Step 1: 提取字幕 ====================
extract_srt() {
    local dir="$1"
    local rec="$dir/recording.mov"
    local srt="$dir/subtitles.srt"
    
    [ ! -f "$rec" ] && { err "找不到 $rec"; return 1; }
    
    # 检查模型是否已缓存
    local model_cached=0
    case "$ASR_ENGINE" in
      funasr)
        [ -d ~/.cache/modelscope/hub/iic/SenseVoiceSmall ] && model_cached=1 ;;
      openai-whisper|*)
        [ -f ~/.cache/whisper/small.pt ] && model_cached=1 ;;
    esac
    [ "$model_cached" -eq 0 ] && info "首次运行需下载模型 (~500MB)，请耐心等待 2-5 分钟"
    info "识别引擎: $ASR_ENGINE"
    
    (
    python3 - "$dir/_tmp.wav" "$srt" "$ASR_ENGINE" << 'PYEOF'
import sys
audio_file = sys.argv[1]
srt_file = sys.argv[2]
engine = sys.argv[3]

if engine == "funasr":
    from funasr_onnx import SenseVoiceSmall
    import soundfile as sf
    m = SenseVoiceSmall(model_dir="iic/SenseVoiceSmall")
    audio, sr = sf.read(audio_file)
    result = m(audio, language="zh", use_itn=True)
    segments = []
    for seg in result[0].get("timestamp", []):
        if seg:
            segments.append({"start": seg[0]/1000, "end": seg[1]/1000, "text": seg[2]})
    print("[SenseVoice]", end=" ")
elif engine == "openai-whisper":
    import whisper
    model = whisper.load_model("small")
    result = model.transcribe(audio_file, language="zh", verbose=False)
    segments = [{"start": s["start"], "end": s["end"], "text": s["text"].strip()} for s in result["segments"]]
    print("[openai-whisper]", end=" ")
else:
    from faster_whisper import WhisperModel
    model = WhisperModel("small", device="cpu", compute_type="int8")
    segs, _ = model.transcribe(audio_file, language="zh")
    segments = [{"start": s.start, "end": s.end, "text": s.text.strip()} for s in segs]
    print("[faster-whisper]", end=" ")

with open(srt_file, "w") as f:
    for i, seg in enumerate(segments, 1):
        def fmt(t):
            h, m = int(t//3600), int((t%3600)//60)
            s, ms = int(t%60), int((t%1)*1000)
            return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"
        f.write(f"{i}\n{fmt(seg['start'])} --> {fmt(seg['end'])}\n{seg['text']}\n\n")
print(f"{len(segments)} 条字幕")
PYEOF
) &
pid=$!
spinner $pid "Whisper 识别中..."
    
    rm -f "$dir/_tmp.wav"
    ok "字幕已生成: subtitles.srt"
}

# ==================== Step 2: SRT → AI 配音（中文） ====================
srt_to_dub() {
    local dir="$1"
    local srt="${2:-$dir/subtitles.srt}"
    local dub="${3:-$dir/ai_dub.wav}"
    local voice="${4:-$VOICE}"
    
    [ ! -f "$srt" ] && { err "找不到 $srt"; return 1; }
    info "字幕 → AI 配音 ($voice)"
    srt_to_dub_core "$srt" "$dub" "$voice"
    ok "AI 配音: $(basename "$dub")"
}

# ==================== Step 3: 合成 ====================
compose() {
    local dir="$1"
    local rec="$dir/recording.mov"
    local dub="$dir/ai_dub.wav"
    local srt="$dir/subtitles.srt"
    local out="$dir/final.mp4"
    
    [ ! -f "$rec" ] && { err "缺少 recording.mov"; return 1; }
    [ ! -f "$dub" ] && { err "缺少 ai_dub.wav，请先运行 dub"; return 1; }
    
    info "合成最终视频..."
    
    if [ -f "$srt" ]; then
        # 有字幕：烧录进去
        ffmpeg -i "$rec" -i "$dub" \
            -c:v libx264 -preset fast -crf 23 \
            -c:a aac -map 0:v:0 -map 1:a:0 \
            -vf "subtitles=$srt:force_style='FontSize=22,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,Outline=2'" \
            -shortest "$out" -y 2>/dev/null
    else
        # 无字幕：仅替换音频
        ffmpeg -i "$rec" -i "$dub" \
            -c:v libx264 -preset fast -crf 23 \
            -c:a aac -map 0:v:0 -map 1:a:0 \
            -shortest "$out" -y 2>/dev/null
    fi
    
    ok "成片: final.mp4"
}

# ==================== Step 4: 翻译字幕（DeepSeek） ====================
translate_srt() {
    local dir="$1"
    local zh_srt="$dir/subtitles.srt"
    local en_srt="$dir/subtitles_en.srt"
    
    [ ! -f "$zh_srt" ] && { err "找不到 $zh_srt，请先运行 srt"; return 1; }
    [ -z "$DEEPSEEK_KEY" ] && { err "请设置 DEEPSEEK_API_KEY 环境变量"; return 1; }
    
    info "DeepSeek 翻译: 中文 → 英文"
    
    (
    python3 - "$zh_srt" "$en_srt" "$DEEPSEEK_KEY" << 'PYEOF'
import sys, re, json, urllib.request

srt_file = sys.argv[1]
out_file = sys.argv[2]
api_key = sys.argv[3]

# 读取 SRT，提取纯文本
with open(srt_file) as f:
    content = f.read()

# 提取所有字幕文本（保留序号和时间轴）
pattern = r'(\d+\n\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}\n)(.+?)(?=\n\n|\Z)'
matches = re.findall(pattern, content, re.DOTALL)

texts = [m[1].strip().replace('\n', ' ') for m in matches]

# 合并成批量翻译（用 ||| 分隔）
combined = " ||| ".join(texts)

# 调用 DeepSeek API
req = urllib.request.Request(
    "https://api.deepseek.com/chat/completions",
    data=json.dumps({
        "model": "deepseek-chat",
        "messages": [
            {"role": "system", "content": "你是一个技术文档翻译专家。将以下中文逐句翻译成英文。每句用 ||| 分隔，保持原有顺序。只返回译文，不要解释。"},
            {"role": "user", "content": combined}
        ],
        "temperature": 0.3
    }).encode(),
    headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
)

resp = json.loads(urllib.request.urlopen(req).read())
translated = resp["choices"][0]["message"]["content"].strip()

# 拆分回逐句
en_texts = [t.strip() for t in translated.split("|||")]

# 写入英文 SRT
with open(out_file, "w") as f:
    for i, (header, _) in enumerate(matches):
        if i < len(en_texts):
            f.write(f"{header}{en_texts[i]}\n\n")

print(f"  翻译完成: {len(en_texts)} 条")
PYEOF
) &
pid=$!
spinner $pid "DeepSeek 翻译中..."
    
    ok "英文字幕: subtitles_en.srt"
}

# ==================== Step 2-en: 英文字幕 → 英文配音 ====================
srt_to_dub_en() {
    local dir="$1"
    local srt="$dir/subtitles_en.srt"
    local dub="$dir/ai_dub_en.wav"
    
    [ ! -f "$srt" ] && { err "找不到 $srt，请先运行 trans"; return 1; }
    info "英文字幕 → AI 配音 ($VOICE_EN)"
    srt_to_dub_core "$srt" "$dub" "$VOICE_EN"
    ok "英文 AI 配音: ai_dub_en.wav"
}

# 配音核心 — 使用 edge-tts（微软神经语音，自然度远高于 say）
srt_to_dub_core() {
    local srt="$1"
    local dub="$2"
    local voice="$3"
    local edge="${EDGE_TTS:-edge-tts}"
    
    if [ ! -x "$edge" ] && ! command -v edge-tts &>/dev/null; then
        # 回退到 macOS say
        warn "edge-tts 不可用，回退到 macOS say"
        srt_to_dub_say "$srt" "$dub" "$voice"
        return
    fi
    
    (
    python3 - "$srt" "$dub" "$voice" "$edge" << 'PYEOF'
import sys, re, os, subprocess, tempfile
srt_file = sys.argv[1]; out_wav = sys.argv[2]; voice = sys.argv[3]; edge = sys.argv[4]

with open(srt_file) as f: content = f.read()
pattern = r'(\d+)\n(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})\n(.+?)(?=\n\n|\Z)'
matches = re.findall(pattern, content, re.DOTALL)

def to_sec(t):
    h, m, s = t.split(':'); s, ms = s.split(',')
    return int(h)*3600 + int(m)*60 + int(s) + int(ms)/1000

tmpdir = tempfile.mkdtemp()
concat = os.path.join(tmpdir, "concat.txt")

with open(concat, "w") as cl:
    for m in matches:
        idx, t1, t2, text = m
        text = text.strip().replace('\n', ' ')
        seg_num = int(idx); target_dur = to_sec(t2) - to_sec(t1)
        mp3 = os.path.join(tmpdir, f"seg_{seg_num:03d}.mp3")
        wav = os.path.join(tmpdir, f"seg_{seg_num:03d}.wav")
        
        # edge-tts 生成 mp3
        subprocess.run([edge, "--voice", voice, "--text", text, "--write-media", mp3],
                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # 转 wav + atempo 调速
        subprocess.run(["ffmpeg", "-i", mp3, wav, "-y"],
                      stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        os.remove(mp3)
        
        result = subprocess.run(["ffprobe", "-v", "quiet", "-show_entries", "format=duration",
                                "-of", "csv=p=0", wav], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        ai_dur = float(result.stdout.strip() or 2.0)
        
        if abs(ai_dur - target_dur) > 0.5 and ai_dur > 0:
            tempo = max(min(ai_dur / target_dur, 2.0), 0.5)
            tmp_wav = os.path.join(tmpdir, "_adj.wav")
            subprocess.run(["ffmpeg", "-i", wav, "-filter:a", f"atempo={tempo:.3f}", tmp_wav, "-y"],
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            os.rename(tmp_wav, wav)
        
        cl.write(f"file '{wav}'\n")
        print(f"  [{seg_num}/{len(matches)}] {text[:40]}...", flush=True)

subprocess.run(["ffmpeg", "-f", "concat", "-safe", "0", "-i", concat, "-c", "copy", out_wav, "-y"],
              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
import shutil; shutil.rmtree(tmpdir, ignore_errors=True)
PYEOF
) &
pid=$!
spinner $pid "AI 配音生成中..."
}

# say 回退（edge-tts 不可用时）
srt_to_dub_say() {
    local srt="$1"
    local dub="$2"
    local voice="$3"
    
    python3 - "$srt" "$dub" "${voice:-Tingting}" << 'PYEOF'
import sys, re, os, subprocess, tempfile
srt_file = sys.argv[1]; out_wav = sys.argv[2]; voice = sys.argv[3]

with open(srt_file) as f: content = f.read()
pattern = r'(\d+)\n(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})\n(.+?)(?=\n\n|\Z)'
matches = re.findall(pattern, content, re.DOTALL)

def to_sec(t):
    h, m, s = t.split(':'); s, ms = s.split(',')
    return int(h)*3600 + int(m)*60 + int(s) + int(ms)/1000

tmpdir = tempfile.mkdtemp()
concat = os.path.join(tmpdir, "concat.txt")

with open(concat, "w") as cl:
    for m in matches:
        idx, t1, t2, text = m
        text = text.strip().replace('\n', ' '); seg_num = int(idx)
        target_dur = to_sec(t2) - to_sec(t1)
        aiff = os.path.join(tmpdir, f"_s.aiff")
        wav = os.path.join(tmpdir, f"seg_{seg_num:03d}.wav")
        subprocess.run(["say", "-v", voice, "-o", aiff, text], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        subprocess.run(["ffmpeg", "-i", aiff, wav, "-y"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        os.remove(aiff)
        result = subprocess.run(["afinfo", wav], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        ai_dur = 2.0
        for line in result.stdout.split('\n'):
            if 'duration:' in line: ai_dur = float(line.split(':')[1].strip()); break
        if abs(ai_dur - target_dur) > 0.3 and ai_dur > 0:
            tempo = max(min(ai_dur / target_dur, 2.0), 0.5)
            tmp_wav = os.path.join(tmpdir, "_adj.wav")
            subprocess.run(["ffmpeg", "-i", wav, "-filter:a", f"atempo={tempo:.3f}", tmp_wav, "-y"],
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            os.rename(tmp_wav, wav)
        cl.write(f"file '{wav}'\n")
        print(f"  [{seg_num}/{len(matches)}] {text[:30]}...", flush=True)

subprocess.run(["ffmpeg", "-f", "concat", "-safe", "0", "-i", concat, "-c", "copy", out_wav, "-y"],
              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
import shutil; shutil.rmtree(tmpdir, ignore_errors=True)
PYEOF
}

# ==================== 英文合成 ====================
compose_en() {
    local dir="$1"
    local rec="$dir/recording.mov"
    local dub="$dir/ai_dub_en.wav"
    local srt="$dir/subtitles_en.srt"
    local out="$dir/final_en.mp4"
    
    [ ! -f "$rec" ] && { err "缺少 recording.mov"; return 1; }
    [ ! -f "$dub" ] && { err "缺少 ai_dub_en.wav"; return 1; }
    
    info "合成英文视频..."
    
    if [ -f "$srt" ]; then
        ffmpeg -i "$rec" -i "$dub" \
            -c:v libx264 -preset fast -crf 23 \
            -c:a aac -map 0:v:0 -map 1:a:0 \
            -vf "subtitles=$srt:force_style='FontSize=22,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,Outline=2'" \
            -shortest "$out" -y 2>/dev/null
    else
        ffmpeg -i "$rec" -i "$dub" \
            -c:v libx264 -preset fast -crf 23 \
            -c:a aac -map 0:v:0 -map 1:a:0 \
            -shortest "$out" -y 2>/dev/null
    fi
    
    ok "英文成片: final_en.mp4"
}

# ==================== 英文全流程 ====================
cmd_en() {
    local dir="$1"
    [ -z "$DEEPSEEK_KEY" ] && { err "请设置环境变量: export DEEPSEEK_API_KEY=sk-xxx"; return 1; }
    
    info "英文全流程: $(basename "$dir")"
    echo ""
    
    # 如果字幕还没提取，先提取
    [ ! -f "$dir/subtitles.srt" ] && { check_env || return 1; extract_srt "$dir" || return 1; echo ""; }
    
    translate_srt "$dir" || return 1
    echo ""
    srt_to_dub_en "$dir" || return 1
    echo ""
    compose_en "$dir" || return 1
    echo ""
    ok "英文版完成！"
    show_status "$dir"
    [ -f "$dir/final_en.mp4" ] && ok "final_en.mp4 ($(du -h "$dir/final_en.mp4" | cut -f1))"
}

cmd_trans() {
    local dir="$1"
    [ -z "$DEEPSEEK_KEY" ] && { err "请设置环境变量: export DEEPSEEK_API_KEY=sk-xxx"; return 1; }
    translate_srt "$dir"
}

cmd_dub_en() {
    local dir="$1"
    srt_to_dub_en "$dir"
}

cmd_mix_en() {
    local dir="$1"
    compose_en "$dir"
}
cmd_all() {
    local dir="$1"
    info "全流程: $(basename "$dir")"
    echo ""
    check_env || return 1
    extract_srt "$dir" || return 1
    echo ""
    srt_to_dub "$dir" || return 1
    echo ""
    compose "$dir" || return 1
    echo ""
    ok "全部完成！"
    show_status "$dir"
}

cmd_srt() {
    local dir="$1"
    check_env || return 1
    extract_srt "$dir"
}

cmd_dub() {
    local dir="$1"
    # 只需要 say + ffmpeg，不需要 whisper
    srt_to_dub "$dir"
}

cmd_mix() {
    local dir="$1"
    compose "$dir"
}

cmd_status() {
    if [ "$1" = "--all" ]; then
        for d in "$BASE"/feature-*/; do
            show_status "$d"
        done
    else
        show_status "$1"
    fi
}

# ==================== 入口 ====================
case "${1:-}" in
    all)    dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_all "$dir" ;;
    srt)    dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_srt "$dir" ;;
    dub)    dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_dub "$dir" ;;
    mix)    dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_mix "$dir" ;;
    trans)  dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_trans "$dir" ;;
    en)     dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_en "$dir" ;;
    dub-en) dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_dub_en "$dir" ;;
    mix-en) dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_mix_en "$dir" ;;
    status) cmd_status "${2:-}" ;;
    *)
        echo "录屏处理工具"
        echo ""
        echo "用法:"
        echo "  $0 all     <feature>    全流程: 字幕→AI配音→合成"
        echo "  $0 srt     <feature>    仅提取字幕（需要 Whisper）"
        echo "  $0 dub     <feature>    仅生成 AI 配音（试听用）"
        echo "  $0 mix     <feature>    仅合成视频"
        echo ""
        echo "  $0 trans   <feature>    翻译字幕: 中文→英文 (DeepSeek)"
        echo "  $0 en      <feature>    英文全流程: 翻译→配音→合成"
        echo "  $0 dub-en  <feature>    仅生成英文配音"
        echo "  $0 mix-en  <feature>    仅合成英文视频"
        echo ""
        echo "  $0 status  <feature>    查看状态"
        echo "  $0 status  --all        查看全部 feature 状态"
        echo ""
        echo "环境变量:"
        echo "  export DEEPSEEK_API_KEY=sk-xxx    （trans/en 必需）"
        echo "  export VIDEO_ASR=faster-whisper    ASR 引擎（默认）"
        echo "              =openai-whisper        OpenAI Whisper"
        echo "              =funasr                SenseVoice (需先安装)"
        echo ""
        echo "约定文件名（每个 feature 目录下）:"
        echo "  recording.mov      原始录屏"
        echo "  subtitles.srt      中文字幕"
        echo "  subtitles_en.srt   英文字幕"
        echo "  ai_dub.wav         中文 AI 配音"
        echo "  ai_dub_en.wav      英文 AI 配音"
        echo "  final.mp4          中文成片"
        echo "  final_en.mp4       英文成片"
        ;;
esac
