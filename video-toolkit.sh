#!/bin/bash
# ============================================================
# 录屏处理工具 — 一键从录屏到成片
# ============================================================
# 自动启用 .venv
if [ -z "$VIRTUAL_ENV" ] && [ -f "$(dirname "$0")/.venv/bin/activate" ]; then
  source "$(dirname "$0")/.venv/bin/activate"
fi

# TRACE 模式：生成可回放的脚本录制文件
if [ "${TRACE:-0}" = "1" ]; then
  TRACE_FILE="${TRACE_FILE:-${VIDEO_FEATURES_DIR:-$PWD}/trace-$(date +%H%M%S).sh}"
  echo "#!/bin/bash" > "$TRACE_FILE"
  echo "# Video Toolkit trace — $(date)" >> "$TRACE_FILE"
  echo "set -e" >> "$TRACE_FILE"
  echo "▶ TRACE: $TRACE_FILE"
  export PS4='+ '
  exec 2> >(tee -a "$TRACE_FILE" >&2)
  set -x
fi
# 约定文件名（每个 feature 目录下）:
#   feature-XX-name/
#   ├── recording.mov   原始录屏
#   ├── subtitles.srt   字幕（自动生成或手写）
#   ├── ai_dub.wav      AI 配音
#   └── final.mp4       最终成片
#
# 用法:
#   curl -sSf https://video-toolkit.bitey.ai/install.sh | bash   安装
#   vt all    <feature>    全流程
#   vt srt    <feature>    仅提取字幕
#   vt dub    <feature>    仅生成AI配音
#   vt mix    <feature>    仅合成视频
#   vt en     <feature>    英文全流程
#   vt status <feature>    查看状态
# ============================================================
set -e

BASE="${VIDEO_FEATURES_DIR:-$PWD}"  # 默认搜索当前目录，可设 VIDEO_FEATURES_DIR
TOOLKIT="$(cd "$(dirname "$0")" && pwd)"
VOICE="${VIDEO_VOICE:-zh-CN-XiaoxiaoNeural}"    # 微软神经语音（最自然）
VOICE_EN="${VIDEO_VOICE_EN:-en-US-AvaNeural}"        # 美式英文，清晰亲和
EDGE_TTS="$TOOLKIT/.venv/bin/edge-tts"  # edge-tts 路径
ASR_ENGINE="${VIDEO_ASR:-faster-whisper}"   # faster-whisper | openai-whisper | funasr
DEEPSEEK_KEY="${DEEPSEEK_API_KEY:-}"   # 优先环境变量
# 其次从 ~/.aas_deepseek_key 读取（仅本机）
[ -z "$DEEPSEEK_KEY" ] && [ -f "$HOME/.aas_deepseek_key" ] && DEEPSEEK_KEY=$(cat "$HOME/.aas_deepseek_key" 2>/dev/null)
# 再次从 config 读取
if [ -f "$HOME/.config/video-toolkit/config" ]; then
    [ -z "$DEEPSEEK_KEY" ] && DEEPSEEK_KEY=$(grep '^DEEPSEEK_API_KEY=' "$HOME/.config/video-toolkit/config" 2>/dev/null | cut -d= -f2-)
    [ "$VOICE" = "zh-CN-XiaoxiaoNeural" ] && VOICE=$(grep '^VIDEO_VOICE=' "$HOME/.config/video-toolkit/config" 2>/dev/null | cut -d= -f2-)
    [ "$VOICE" = "zh-CN-XiaoxiaoNeural" ] || : # keep if set by env
    [ "$VOICE_EN" = "en-US-AvaNeural" ] && VOICE_EN=$(grep '^VIDEO_VOICE_EN=' "$HOME/.config/video-toolkit/config" 2>/dev/null | cut -d= -f2-)
    [ "$ASR_ENGINE" = "faster-whisper" ] && ASR_ENGINE=$(grep '^VIDEO_ASR=' "$HOME/.config/video-toolkit/config" 2>/dev/null | cut -d= -f2-)
fi

# ── 加载 v2 模块 ──
TOOLKIT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$TOOLKIT_DIR/lib/meta.sh" ] && source "$TOOLKIT_DIR/lib/meta.sh"
[ -f "$TOOLKIT_DIR/lib/compose.sh" ] && source "$TOOLKIT_DIR/lib/compose.sh"
[ -f "$TOOLKIT_DIR/lib/slides.sh" ] && source "$TOOLKIT_DIR/lib/slides.sh"

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
    # 1. 绝对/相对路径 → 直接使用
    if [ -d "$name" ] && [[ "$name" == */* ]]; then
        echo "$(cd "$name" && pwd)"
        return
    fi
    # 2. 当前目录精确匹配
    if [ -d "$BASE/$name" ]; then
        echo "$BASE/$name"
        return
    fi
    # 3. 编号简写: 01 → feature-01-*
    local pattern="$BASE/feature-${name#feature-}*"
    local matches=($pattern)
    if [ -d "${matches[0]}" ]; then
        echo "${matches[0]}"
        return
    fi
    # 4. 在当前目录也搜一次（如果是纯编号）
    if [ -d "$name" ]; then
        echo "$(cd "$name" && pwd)"
        return
    fi
    echo ""
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
    local out="$dir/$(basename "$dir").mp4"
    
    local en_srt="$dir/subtitles_en.srt"
    local en_dub="$dir/ai_dub_en.wav"
    local en_out="$dir/$(basename "$dir")_en.mp4"
    
    [ -f "$rec" ]   && ok "recording.mov   ($(du -h "$rec" | cut -f1))"    || warn "recording.mov   缺失"
    [ -f "$srt" ]   && ok "subtitles.srt   ($(grep -c '^[0-9]' "$srt" 2>/dev/null || echo 0) 条)"  || warn "subtitles.srt   缺失"
    [ -f "$dub" ]   && ok "ai_dub.wav      ($(du -h "$dub" | cut -f1))"     || warn "ai_dub.wav      缺失"
    [ -f "$out" ]   && ok "$(basename "$out")       ($(du -h "$out" | cut -f1))"     || warn "$(basename "$dir").mp4       缺失"
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
      openai-whisper)
        [ -f ~/.cache/whisper/small.pt ] && model_cached=1 ;;
      *)
        [ -d ~/.cache/huggingface/hub/models--Systran--faster-whisper-small ] && model_cached=1
        [ -f ~/.cache/whisper/small.pt ] && model_cached=1 ;;
    esac
    [ "$model_cached" -eq 0 ] && info "首次运行需下载模型 (~500MB)，请耐心等待 2-5 分钟"
    info "识别引擎: $ASR_ENGINE"
    
    ffmpeg -i "$rec" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$dir/_tmp.wav" -y 2>/dev/null
    
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
    local out="$dir/$(basename "$dir").mp4"
    
    [ ! -f "$rec" ] && { err "缺少 recording.mov"; return 1; }
    [ ! -f "$dub" ] && { err "缺少 ai_dub.wav，请先运行 dub"; return 1; }
    
    # 生成 AI 配音替换后的中间视频
    info "生成 AI 配音视频..."
    local content="$dir/_dubbed.mp4"
    ffmpeg -i "$rec" -i "$dub" \
        -c:v h264_videotoolbox -b:v 5M -r 30 -vf "scale=1920:-2" \
        -c:a aac -ar 48000 -map 0:v:0 -map 1:a:0 -shortest "$content" -y 2>/dev/null
    
    # 统一走 compose_final（无 meta 时自动使用默认值）
    local meta=$(load_meta "$dir" 2>/dev/null || echo "{}")
    compose_final "$content" "$meta" "$dir" "$out"
    rm -f "$content"
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
data = json.dumps({
    "model": "deepseek-v4-flash",
    "messages": [
        {"role": "system", "content": "你是一个技术文档翻译专家。将以下中文逐句翻译成英文。每句用 ||| 分隔，保持原有顺序。只返回译文，不要解释。"},
        {"role": "user", "content": combined}
    ],
    "temperature": 0.3
}).encode()

if len(sys.argv) > 4 and sys.argv[4] == "--verbose":
    print(f"  [DEBUG] API Key: {api_key[:10]}...{api_key[-4:]}")
    print(f"  [DEBUG] Texts: {len(texts)} sentences")
    print(f"  [DEBUG] Body size: {len(data)} bytes")

req = urllib.request.Request(
    "https://api.deepseek.com/v1/chat/completions",
    data=data,
    headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
)

try:
    resp = json.loads(urllib.request.urlopen(req).read())
    translated = resp["choices"][0]["message"]["content"].strip()
except urllib.error.HTTPError as e:
    body = e.read().decode()
    print(f"  [ERROR] HTTP {e.code}: {body[:500]}", file=sys.stderr)
    raise

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

# 生成静默模板
silence_tpl = os.path.join(tmpdir, "_silence.wav")
subprocess.run(["ffmpeg", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono", "-t", "0.1", silence_tpl, "-y"],
              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

prev_end = 0.0
with open(concat, "w") as cl:
    for m in matches:
        idx, t1, t2, text = m
        text = text.strip().replace('\n', ' ')
        if not text: continue   # 跳过空字幕行
        seg_num = int(idx)
        seg_start = to_sec(t1)
        seg_end = to_sec(t2)
        target_dur = seg_end - seg_start
        
        # 段间静默：保持时间轴对齐
        gap = seg_start - prev_end
        if gap > 0.3:
            gap_wav = os.path.join(tmpdir, f"gap_{seg_num:03d}.wav")
            subprocess.run(["ffmpeg", "-f", "lavfi", "-i", f"anullsrc=r=24000:cl=mono", "-t", f"{gap:.2f}", gap_wav, "-y"],
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            cl.write(f"file '{gap_wav}'\n")
        
        mp3 = os.path.join(tmpdir, f"seg_{seg_num:03d}.mp3")
        wav = os.path.join(tmpdir, f"seg_{seg_num:03d}.wav")
        
        # edge-tts 生成 mp3
        subprocess.run([edge, "--voice", voice, "--text", text, "--write-media", mp3],
                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # 转 wav（自然语速，不调整）
        subprocess.run(["ffmpeg", "-i", mp3, wav, "-y"],
                      stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        os.remove(mp3)
        
        cl.write(f"file '{wav}'\n")
        # 获取 AI 配音实际时长
        result = subprocess.run(["ffprobe", "-v", "quiet", "-show_entries", "format=duration",
                                "-of", "csv=p=0", wav], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        actual_dur = float(result.stdout.strip() or target_dur)
        prev_end = prev_end + (gap if gap > 0.3 else 0) + actual_dur
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
    local out="$dir/$(basename "$dir")_en.mp4"
    
    [ ! -f "$rec" ] && { err "缺少 recording.mov"; return 1; }
    [ ! -f "$dub" ] && { err "缺少 ai_dub_en.wav"; return 1; }
    
    info "合成英文视频..."
    
    # 后台执行 ffmpeg + 旋转等待
    (
    if [ -f "$srt" ] && [ "${VIDEO_BURN_SUB:-1}" != "0" ] && ffmpeg -filters 2>/dev/null | grep -qE " ass |libass"; then
        ffmpeg -i "$srt" /tmp/_vt_sub_en.ass -y 2>/dev/null
        ffmpeg -i "$rec" -i "$dub" \
            -c:v h264_videotoolbox -b:v 5M -r 30 -vf "scale=1920:-2" \
            -c:a aac -map 0:v:0 -map 1:a:0 \
            -vf "scale=1920:-2,ass=filename=/tmp/_vt_sub.ass" \
            -shortest "$out" -y 2>/dev/null
        rm -f /tmp/_vt_sub_en.ass
    else
        ffmpeg -i "$rec" -i "$dub" \
            -c:v h264_videotoolbox -b:v 5M -r 30 -vf "scale=1920:-2" \
            -c:a aac -map 0:v:0 -map 1:a:0 \
            -shortest "$out" -y 2>/dev/null
    fi
    ) &
    pid=$!
    spinner $pid "视频合成中..."
    
    if [ "${VIDEO_BURN_SUB:-0}" = "1" ] && [ -f "$srt" ] && ! ffmpeg -filters 2>/dev/null | grep -qE " ass |libass"; then warn "字幕未烧录 (ffmpeg 无 libass)"; fi
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
    [ -f "$dir/$(basename "$dir")_en.mp4" ] && ok "final_en.mp4 ($(du -h "$dir/$(basename "$dir")_en.mp4" | cut -f1))"
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

# ── 合成（包装 compose_final） ──
# ── 自动化录制 ──
cmd_record() {
    local dir="$1"
    local rec="$dir/recording.mov"
    
    # 如果已有 Playwright 脚本
    if [ -f "$dir/record.spec.js" ]; then
        info "Playwright 自动化 + 录屏: $(basename "$dir")"
        
        # 安装 Playwright（如果需要）
        if ! npx playwright --version 2>/dev/null; then
            warn "安装 Playwright..."
            npm install -g playwright 2>/dev/null && npx playwright install chromium 2>/dev/null
        fi
        
        # 启动 ffmpeg 录屏（后台）
        info "开始录屏 → $rec"
        ffmpeg -f avfoundation -i "1:none" -c:v libx264 -preset ultrafast -crf 28 "$rec" -y 2>/dev/null &
        local ffmpeg_pid=$!
        sleep 1
        
        # 运行 Playwright 自动化
        export BASE_URL="${BASE_URL:-http://localhost:6888}"
        export ADMIN_URL="${ADMIN_URL:-https://localhost:6848}"
        export VT_TIMELINE="$dir/timeline.json"
        npx playwright test "$dir/record.spec.js" --headed --timeout=120000
        
        # 停止录屏
        kill "$ffmpeg_pid" 2>/dev/null
        wait "$ffmpeg_pid" 2>/dev/null
        
        # timeline.json → subtitles.srt
        if [ -f "$dir/timeline.json" ]; then
            local srt="$dir/subtitles.srt"
            python3 -c "
import json
tl = json.load(open('$dir/timeline.json'))
lines = []
for i, s in enumerate(tl):
    t = s['t']
    next_t = tl[i+1]['t'] if i+1 < len(tl) else t + 5
    t1 = f'{int(t//3600):02d}:{int((t%3600)//60):02d}:{int(t%60):02d},{int((t%1)*1000):03d}'
    t2 = f'{int(next_t//3600):02d}:{int((next_t%3600)//60):02d}:{int(next_t%60):02d},{int((next_t%1)*1000):03d}'
    lines.append(f'{i+1}\n{t1} --> {t2}\n{s[\"text\"]}\n')
with open('$srt','w') as f: f.write('\n'.join(lines))
print(f'✅ SRT: {len(lines)} 段')
" 2>/dev/null
            ok "字幕: $srt"
        fi
    else
        # 回退：纯录屏
        info "录屏 (Ctrl+C 停止) → $rec"
        ffmpeg -f avfoundation -i "1:none" -c:v libx264 -preset ultrafast -crf 28 "$rec" -y
    fi
    ok "录制完成: $rec"
}

# ── 封面预览 ──
cmd_cover() {
    local dir="$1"
    local meta=$(load_meta "$dir" 2>/dev/null || echo "{}")
    local title=$(meta_get "$meta" "title")
    local subtitle=$(meta_get "$meta" "subtitle")
    local dur=$(meta_get "$meta" "cover_duration")
    local out="$dir/_cover_test.mp4"
    local logo=$(resolve_asset "$dir" "$meta" "logo")
    local company=$(meta_get "$meta" "company")
    [ -z "$title" ] && { err "meta.json 缺少 title"; return 1; }
    info "生成封面预览: $title"
    gen_title_card "$title" "${subtitle:-}" "${dur:-3}" "$out" "$logo" "$company"
    [ -f "$out" ] && { open "$out" 2>/dev/null || xdg-open "$out" 2>/dev/null; ok "封面预览 (${dur:-3}s)" ; } || err "生成失败"
}

cmd_mix() {
    local dir="$1"
    compose "$dir"
}
cmd_all() {
    local dir="$1"
    info "全流程: $(basename "$dir")"

    # v2: 尝试加载 meta.json
    local meta=$(load_meta "$dir" 2>/dev/null || echo "{}")
    local type=$(detect_type "$dir" "$meta" 2>/dev/null || echo "video")

    case "$type" in
      slide)
        info "幻灯片模式"
        local pages=$(build_pages "$dir" "$meta")
        local content="$dir/_content.mp4"
        gen_slide_video "$pages" "$meta" "$dir" "$content"
        compose_final "$content" "$meta" "$dir" "$dir/$(basename "$dir").mp4"
        rm -f "$content"
        ok "$(basename "$dir").mp4"
        return
        ;;
      error:*)
        warn "${type#error: }"
        ;;
    esac

    # 默认 video 模式（向后兼容）
    echo ""
    check_env || return 1
    extract_srt "$dir" || return 1
    echo ""
    srt_to_dub "$dir" || return 1
    echo ""
    compose "$dir"
    echo ""
    ok "$(basename "$dir").mp4"
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

# ==================== 幻灯片自动生成 ====================
cmd_slide_v2() {
    local dir="$1"
    info "幻灯片模式: $(basename "$dir")"
    local meta=$(load_meta "$dir" 2>/dev/null || echo "{}")
    local pages=$(build_pages "$dir" "$meta")
    local content="$dir/_content.mp4"
    
    # 智能缓存：clips未变 + meta未变 → 跳过
    if [ "${FORCE:-0}" != "1" ] && [ -f "$dir/$(basename "$dir").mp4" ]; then
      local newer=1
      # 1. 检查所有 page clips 是否比 final.mp4 新
      for clip in "$dir/_clips"/page_*.mp4; do
        [ -f "$clip" ] && [ "$clip" -nt "$dir/$(basename "$dir").mp4" ] && newer=0 && break
      done
      # 2. 检查 meta.json 是否比 final.mp4 新
      [ -f "$dir/meta.json" ] && [ "$dir/meta.json" -nt "$dir/$(basename "$dir").mp4" ] && newer=0
      [ -f "$(dirname "$dir")/meta.json" ] && [ "$(dirname "$dir")/meta.json" -nt "$dir/$(basename "$dir").mp4" ] && newer=0
      if [ "$newer" -eq 1 ]; then
        info "clips 和 meta 均未变化，跳过合成"
        return
      fi
    fi
    
    gen_slide_video "$pages" "$meta" "$dir" "$content"
    compose_final "$content" "$meta" "$dir" "$dir/$(basename "$dir").mp4"
    rm -f "$content"
}

# ── config 命令 ──
cmd_config() {
    local cfg="$HOME/.config/video-toolkit/config"
    local sub="$1" val="$2"
    case "$sub" in
        "") cat "$cfg" 2>/dev/null || echo "(空)" ;;
        "list")
            case "$val" in
                voice|voices)
                    echo "中文: zh-CN-XiaoxiaoNeural ★ 温暖清晰"
                    echo "      zh-CN-YunyangNeural · 专业稳重"
                    echo "      zh-CN-YunjianNeural · 激情洋溢"
                    echo "      zh-CN-YunxiNeural   · 活泼可爱"
                    echo "英文: en-US-AvaNeural     ★ 清晰亲和"
                    echo "      en-US-AriaNeural    · 自信大方"
                    echo "      en-GB-SoniaNeural   · 英式女声"
                    ;;
                asr)
                    echo "faster-whisper  ★ CTranslate2 加速"
                    echo "openai-whisper    原始 OpenAI"
                    echo "funasr           阿里 SenseVoice"
                    ;;
                *) echo "用法: vt config list <voice|asr>" ;;
            esac ;;
        *=*) 
            local k="${sub%%=*}" v="${sub#*=}"
            [ -f "$cfg" ] || touch "$cfg"
            if grep -q "^${k}=" "$cfg" 2>/dev/null; then
                sed -i.bak "s/^${k}=.*/${k}=${v}/" "$cfg" 2>/dev/null
            else
                echo "${k}=${v}" >> "$cfg"
            fi
            echo "✅ $k=$v" ;;
        *) echo "用法: vt config [KEY=value|list voice|list asr]" ;;
    esac
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
    cover)  dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_cover "$dir" ;;
    record) dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_record "$dir" ;;
    trans)  dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_trans "$dir" ;;
    en)     dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_en "$dir" ;;
    dub-en) dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_dub_en "$dir" ;;
    mix-en) dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_mix_en "$dir" ;;
    slide)  dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_slide_v2 "$dir" ;;  
    play)
      dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }
      case "${3:-}" in
        dub)     afplay "$dir/ai_dub.wav" 2>/dev/null || err "播放失败" ;;
        dub-en)  afplay "$dir/ai_dub_en.wav" 2>/dev/null || err "播放失败" ;;
        final)   open "$dir/$(basename "$dir").mp4" 2>/dev/null || xdg-open "$dir/$(basename "$dir").mp4" 2>/dev/null || err "播放失败" ;;
        final-en) open "$dir/$(basename "$dir")_en.mp4" 2>/dev/null || xdg-open "$dir/$(basename "$dir")_en.mp4" 2>/dev/null || err "播放失败" ;;
        *)
          echo "可用资源:"
          [ -f "$dir/ai_dub.wav" ]    && echo "  dub     → ai_dub.wav ($(ls -lh "$dir/ai_dub.wav" | awk '{print $5}'))"
          [ -f "$dir/ai_dub_en.wav" ] && echo "  dub-en  → ai_dub_en.wav ($(ls -lh "$dir/ai_dub_en.wav" | awk '{print $5}'))"
          [ -f "$dir/$(basename "$dir").mp4" ]     && echo "  final   → final.mp4 ($(ls -lh "$dir/$(basename "$dir").mp4" | awk '{print $5}'))"
          [ -f "$dir/$(basename "$dir")_en.mp4" ]  && echo "  final-en → final_en.mp4 ($(ls -lh "$dir/$(basename "$dir")_en.mp4" | awk '{print $5}'))"
          echo ""
          err "用法: vt play <feature> <dub|dub-en|final|final-en>" ;;
      esac ;;  
    status) cmd_status "${2:-}" ;;
    config) cmd_config "${2:-}" "${3:-}" ;;
    --version) echo "Video Toolkit v2 ($(cat "$TOOLKIT_DIR/VERSION" 2>/dev/null || echo "?"))" ;;
    --update) echo "请用 vt upgrade 命令更新" ;;
    *)
        echo "Video Toolkit — 录屏处理工具 v2"
        echo ""
        echo "用法:"
        echo "  vt all     <feature>    全流程: 字幕→AI配音→合成 (自动检测 slide/video)"
        echo "  vt srt     <feature>    仅提取字幕"
        echo "  vt dub     <feature>    仅生成 AI 配音"
        echo "  vt mix     <feature>    合成视频 + 可选 cover/outro/bgm"
        echo ""
        echo "  vt slide   <feature>    幻灯片模式 (截图+解说→视频)"
        echo ""
        echo "  vt trans   <feature>    翻译字幕: 中文→英文 (DeepSeek)"
        echo "  vt en      <feature>    英文全流程"
        echo "  vt dub-en  <feature>    仅生成英文配音"
        echo "  vt mix-en  <feature>    仅合成英文视频"
        echo ""
        echo "  vt play    <feature> <dub|dub-en|final|final-en>"
        echo "  vt status  <feature>    查看状态"
        echo "  vt status  --all        查看全部"
        echo "  vt config              查看配置"
        echo "  vt config KEY=value    设置配置"
        echo "  vt config list voice   列出可用语音"
        echo "  vt config list asr     列出 ASR 引擎"
        echo "  vt --version            版本"
        echo "  vt --update             自动更新"
        echo ""
        echo "feature 参数:"
        echo "  01                    编号简写，匹配 feature-01-*"
        echo "  feature-01-name       完整目录名"
        echo "  ../path/to/feature     相对/绝对路径"
        echo ""
        echo "幻灯片模式:"
        echo "  slides/01.png + slides/narration.txt → vt slide XX"
        echo ""
        echo "v2 meta.json 配置见 docs/SPEC.md"
        echo ""
        echo "环境变量:"
        echo "  DEEPSEEK_API_KEY    DeepSeek API Key"
        echo "  VIDEO_ASR           ASR 引擎 (faster-whisper / openai-whisper / funasr)"
        echo "  VIDEO_VOICE         中文 AI 语音 ID"
        echo "  VIDEO_VOICE_EN      英文 AI 语音 ID"
        echo "  VIDEO_BURN_SUB      字幕烧录 (0/1)"
        echo "  VIDEO_FEATURES_DIR  feature 根目录"
        echo "  AAS_ADMIN_PORT      管理端口 (默认 6848)"
        echo ""
        echo "约定文件名（每个 feature 目录下）:"
        echo ""
        echo "  目录结构:"
        echo "    feature-XX-name/                  ← 按此格式命名"
        echo "    ├── recording.mov                 ← 原始录屏"
        echo "    ├── subtitles.srt                 ← 中文字幕"
        echo "    ├── subtitles_en.srt              ← 英文字幕 (可选)"
        echo "    ├── ai_dub.wav                    ← 中文 AI 配音"
        echo "    ├── ai_dub_en.wav                 ← 英文 AI 配音 (可选)"
        echo "    ├── final.mp4                     ← 中文成片"
        echo "    └── final_en.mp4                  ← 英文成片 (可选)"
        echo ""
        echo "  feature 参数简写:"
        echo "    XX                    匹配 feature-XX-* 目录"
        echo "    feature-XX-name       精确目录名"
        echo "    ../path/to/feature     完整相对路径"
        ;;
esac
