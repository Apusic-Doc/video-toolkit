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
[ -f "$TOOLKIT_DIR/lib/edit.sh" ] && source "$TOOLKIT_DIR/lib/edit.sh"
[ -f "$TOOLKIT_DIR/lib/groups.sh" ] && source "$TOOLKIT_DIR/lib/groups.sh"

# ==================== 颜色 ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅${NC} $1"; }
warn() { echo -e "${YELLOW}⚠️${NC} $1"; }
err()  { echo -e "${RED}❌${NC} $1"; }
info() { echo -e "${CYAN}➜${NC} $1"; }

# avfoundation 的屏幕序号（"Capture screen N"）不是稳定 ID，接/拔外接显示器后会重新编号，
# 硬编码序号会导致某次录制悄悄录到错误的屏幕（实测发生过：外接屏被当成录制目标，
# 屏幕上不管显示什么全部录了进去）。这里动态识别出内置/主屏对应哪个序号，每次录制前调用。
detect_recording_screen() {
    # 自动识别偶尔会认错屏（比如多屏环境下识别到的不是用户当前实际在用的那块），
    # 留一个手工兜底：设了 VT_RECORD_SCREEN 就直接用这个序号，不跑下面的自动判断逻辑
    if [ -n "$VT_RECORD_SCREEN" ]; then
        echo "$VT_RECORD_SCREEN"
        return
    fi
    local devices count ext_res idx frame res
    devices=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep "Capture screen" | sed -E 's/.*\[([0-9]+)\].*/\1/')
    count=$(echo "$devices" | wc -l | tr -d ' ')
    if [ "$count" -le 1 ]; then
        echo "$devices" | head -1
        return
    fi
    # 非主屏分辨率通常跟 avfoundation 实际抓到的像素分辨率精确一致（内置 Retina 屏有缩放倍数，不会精确相等），
    # 用这个特征找出外接屏对应的序号并排除，剩下的当作内置/主屏
    ext_res=$(system_profiler SPDisplaysDataType -json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for gpu in data.get('SPDisplaysDataType', []):
        for disp in gpu.get('spdisplays_ndrvs', []):
            if disp.get('spdisplays_main') != 'spdisplays_yes':
                res = disp.get('_spdisplays_resolution', '')
                w, h = res.split(' @ ')[0].split(' x ')
                print(f'{w.strip()}x{h.strip()}')
except Exception:
    pass
" 2>/dev/null)
    for idx in $devices; do
        if [ -n "$ext_res" ]; then
            frame="/tmp/_vt_screen_probe_${idx}_$$.png"
            ffmpeg -f avfoundation -i "$idx:none" -frames:v 1 "$frame" -y 2>/dev/null
            res=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$frame" 2>/dev/null)
            rm -f "$frame"
            [ "$res" = "$ext_res" ] && continue
        fi
        echo "$idx"
        return
    done
    echo "$devices" | head -1
}

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

    # vt record（Playwright 自动化）会从 timeline.json 直接生成准确字幕，
    # 比 ASR 识别更准（原文本，非猜测），且录屏音轨往往没有真人说话，ASR 会跑出垃圾字幕。
    # 字幕文件比录屏新 => 已经是可信来源，不要覆盖。
    if [ -f "$srt" ] && [ "$srt" -nt "$rec" ]; then
        info "字幕已存在且比录屏新（多半来自 vt record 的 timeline），跳过 ASR 识别: $srt"
        info "如需强制重新识别，先删除该文件再运行"
        return 0
    fi

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

    # vt record 会算出"ffmpeg 启动→浏览器真正打开"这段空档的秒数
    # （这段时间屏幕上显示什么不可控，可能露出别的窗口/文件夹名），合成时精确剪掉
    local trim_args=()
    if [ -f "$dir/record-offset.txt" ]; then
        local offset=$(cat "$dir/record-offset.txt")
        if python3 -c "exit(0 if float('$offset') > 0.3 else 1)" 2>/dev/null; then
            local safe_offset=$(python3 -c "print(round(float('$offset') + 0.3, 2))")
            info "裁剪录屏开头 ${safe_offset}s（屏幕内容不进成片）"
            trim_args=(-ss "$safe_offset")
        fi
    fi

    # 配音手工偏移——理论上录制时按实测配音时长停留已经该对齐了，但不同 feature
    # 偶尔还是会感觉到配音跟画面差一点（正数=配音整体延后一点，负数=配音整体提前一点），
    # 留一个手工兜底，在 meta.json 里配 dub_offset（单位秒，默认 0）
    local meta_for_offset=$(load_meta "$dir" 2>/dev/null || echo "{}")
    local dub_offset=$(meta_get "$meta_for_offset" "dub_offset")
    dub_offset="${dub_offset:-0}"
    local dub_input_args=() audio_filter_args=()
    if python3 -c "exit(0 if abs(float('$dub_offset')) > 0.001 else 1)" 2>/dev/null; then
        if python3 -c "exit(0 if float('$dub_offset') < 0 else 1)" 2>/dev/null; then
            local skip=$(python3 -c "print(-float('$dub_offset'))")
            info "配音整体提前 ${skip}s（dub_offset=$dub_offset）"
            dub_input_args=(-ss "$skip")
        else
            info "配音整体延后 ${dub_offset}s（dub_offset=$dub_offset）"
            local delay_ms=$(python3 -c "print(int(float('$dub_offset')*1000))")
            audio_filter_args=(-af "adelay=${delay_ms}|${delay_ms}")
        fi
    fi

    # 正数 dub_offset 会让配音总时长变成 "原配音时长 + 偏移"，如果这个值超过录屏本身的
    # 时长，下面的 -shortest 会直接把超出部分的配音截掉（配音说到一半突然没声了，
    # 而不是报错——实测复现，dub_offset=10 配合较短的录屏就会把最后好几句配音吃掉）。
    # 用 tpad 定格最后一帧，把画面垫长到能装下完整配音，不再依赖 -shortest 兜底截断。
    local pad_filter=""
    if python3 -c "exit(0 if float('$dub_offset') > 0.001 else 1)" 2>/dev/null; then
        local video_dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$rec" 2>/dev/null)
        local trimmed_video_dur="$video_dur"
        if [ -n "${safe_offset:-}" ]; then
            trimmed_video_dur=$(python3 -c "print(max(0, float('$video_dur') - float('$safe_offset')))")
        fi
        local dub_dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dub" 2>/dev/null)
        local needed_dur=$(python3 -c "print(float('$dub_dur') + float('$dub_offset'))")
        if python3 -c "exit(0 if float('$needed_dur') > float('$trimmed_video_dur') else 1)" 2>/dev/null; then
            local pad_secs=$(python3 -c "print(round(float('$needed_dur') - float('$trimmed_video_dur') + 0.3, 2))")
            info "配音延后后总时长超出录屏画面，定格最后一帧延长 ${pad_secs}s，避免配音被截断"
            pad_filter=",tpad=stop_mode=clone:stop_duration=${pad_secs}"
        fi
    fi

    # 生成 AI 配音替换后的中间视频
    info "生成 AI 配音视频..."
    local content="$dir/_dubbed.mp4"
    ffmpeg "${trim_args[@]}" -i "$rec" "${dub_input_args[@]}" -i "$dub" \
        -c:v h264_videotoolbox -b:v 5M -r 30 -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black${pad_filter}" -pix_fmt yuv420p \
        -c:a aac -ar 48000 -ac 2 -map 0:v:0 -map 1:a:0 "${audio_filter_args[@]}" -shortest "$content" -y 2>/dev/null
    
    # 统一走 compose_final（无 meta 时自动使用默认值）
    local meta=$(load_meta "$dir" 2>/dev/null || echo "{}")
    compose_final "$content" "$meta" "$dir" "$out"

    # 保留两个版本：带封面（$out）+ 不带封面（画面+配音，没有封面/封底/BGM）
    local no_cover="$dir/$(basename "$dir")-no-cover.mp4"
    cp "$content" "$no_cover"
    rm -f "$content"
    ok "不带封面版本: $no_cover"
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

# edge-tts 的多音字消歧是黑盒模型，偶尔会把"行"这类多音字读错（比如"命令行工具"里的
# "行"被读成 xíng 而不是 háng）——edge-tts 的 Python 库/CLI 都会强制转义输入文本，
# 没有官方渠道能传 SSML <phoneme> 标签强制指定读音，实测确认过（转义后标签变成字面文本被整段读出来）。
# 唯一可靠的办法是换一种不会触发歧义读音的措辞，这里维护一份"问题词→安全替换词"表，
# 发现新的多音字读错，把原词和一个读音安全的替换词加进来就行，一次修复对所有 feature 生效。
POLYPHONE_FIXES = {
    '命令行工具': '命令行',  # "行工具"这个搭配下 edge-tts 偶尔把"行"读成 xíng，去掉"工具"更保险
}

prev_end = 0.0
with open(concat, "w") as cl:
    for m in matches:
        idx, t1, t2, text = m
        text = text.strip().replace('\n', ' ')
        if not text: continue   # 跳过空字幕行
        for bad, good in POLYPHONE_FIXES.items():
            text = text.replace(bad, good)
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

    # 防御：清理任何已存在的、写入同一文件的孤儿 ffmpeg 进程
    # （上次录制若被 Ctrl+C / 终端关闭中断，trap 之前不会走到 kill，会留下后台孤儿）
    local stale_pids=$(pgrep -f "ffmpeg .*avfoundation.*$rec" 2>/dev/null)
    if [ -n "$stale_pids" ]; then
        warn "发现残留录屏进程，清理: $stale_pids"
        kill -9 $stale_pids 2>/dev/null || true
        sleep 1
    fi

    # 每次录制 record.spec.js 都会新建一个 Terminal 窗口（ensureTerminal），
    # 跑多次从不关闭，旧窗口会一直堆在屏幕上，边缘重叠导致画面看起来像文字错乱。
    # quit 之后 macOS/Terminal 默认会"恢复上次窗口"，越关越多；先关掉这个恢复行为，
    # 再用 SIGKILL 而不是正常 quit（避免它有机会保存"下次要恢复"的状态）。
    defaults write com.apple.Terminal NSQuitAlwaysKeepsWindows -bool false 2>/dev/null || true
    pkill -9 -x Terminal 2>/dev/null || true
    sleep 0.5
    # SIGKILL 之前 macOS 已经把窗口状态写进"已保存应用程序状态"了，
    # 跟上面那个偏好设置是两套独立机制，删掉这个才是真正的"下次打开不恢复"
    rm -rf ~/Library/Saved\ Application\ State/com.apple.Terminal.savedState 2>/dev/null || true
    sleep 1

    # 如果已有 Playwright 脚本
    if [ -f "$dir/record.spec.js" ]; then
        info "Playwright 自动化 + 录屏: $(basename "$dir")"

        # 安装 Playwright（如果需要）
        if ! npx playwright --version 2>/dev/null; then
            warn "安装 Playwright..."
            npm install -g playwright 2>/dev/null && npx playwright install chromium 2>/dev/null
        fi

        # 屏幕序号不是稳定 ID，接了外接显示器之后可能会指向错误的屏幕——
        # 动态识别内置/主屏，不要每次都硬编码同一个序号
        local screen_idx=$(detect_recording_screen)
        info "录制屏幕: 序号 $screen_idx（自动识别的内置/主屏）"

        # 运行 Playwright 自动化
        # localhost 在部分机器上 DNS 优先解析成 IPv6，会让"当前是 IPv4/IPv6"之类的
        # 状态角标提前露出、跟叙事对不上（实测复现），默认统一用字面 IPv4 地址
        export BASE_URL="${BASE_URL:-http://127.0.0.1:6888}"
        export ADMIN_URL="${ADMIN_URL:-https://127.0.0.1:6848}"
        export VT_TIMELINE="$dir/timeline.json"
        # 从 config 文件读取密码
        [ -z "$ADMIN_PW" ] && [ -f "$HOME/.config/video-toolkit/config" ] && ADMIN_PW=$(grep '^ADMIN_PW=' "$HOME/.config/video-toolkit/config" 2>/dev/null | cut -d= -f2-)
        export ADMIN_PW
        # NODE_PATH 确保所有模块从同一位置加载，避免 "Requiring second time"
        local cfg="$TOOLKIT_DIR/playwright.config.js"
        export VT_TEST_DIR="$dir"
        local play_bin="$TOOLKIT_DIR/node_modules/.bin/playwright"
        local node_path="$TOOLKIT_DIR/node_modules"
        [ -x "$play_bin" ] || { play_bin="npx playwright"; node_path=""; }
        [ -d "$node_path/@playwright/test" ] || node_path="/Users/martin/Apusic/Product/ApusicAS/Videos/toolkit/node_modules"

        # 先开浏览器、导航好、切到前台，确认"现在开始录屏是安全的"之后才启动 ffmpeg——
        # 而不是先录屏、留几秒空档等浏览器打开再事后裁剪。空档期间屏幕上真实显示的是
        # 别的窗口（出现过好几次真实的敏感内容泄露），裁剪只是补救，raw 文件已经写到磁盘了。
        # ready/go 用文件做跨进程信号：record.spec.js 就绪后写 ready 文件；
        # 这边看到 ready 才启动 ffmpeg，ffmpeg 稳定输出后写 go 文件，脚本收到 go 才开始正式操作。
        local ready_flag="$dir/.record-ready.flag"
        local go_flag="$dir/.record-go.flag"
        rm -f "$ready_flag" "$go_flag"
        export VT_READY_FLAG="$ready_flag"
        export VT_GO_FLAG="$go_flag"

        NODE_PATH="$node_path" "$play_bin" test --config "$cfg" --headed --timeout=600000 &
        local pw_pid=$!

        info "等待浏览器就绪（最多 60 秒）..."
        local waited=0
        while [ ! -f "$ready_flag" ]; do
            sleep 0.5
            waited=$(python3 -c "print($waited + 0.5)")
            if ! kill -0 "$pw_pid" 2>/dev/null; then
                err "Playwright 进程在浏览器就绪前已退出，录屏未启动"
                wait "$pw_pid" 2>/dev/null; pw_exit=$?
                rm -f "$ready_flag" "$go_flag"
                return 1
            fi
            if python3 -c "exit(0 if $waited > 60 else 1)" 2>/dev/null; then
                err "等待浏览器就绪超时（60s），放弃本次录制"
                kill "$pw_pid" 2>/dev/null || true; wait "$pw_pid" 2>/dev/null || true
                rm -f "$ready_flag" "$go_flag"
                return 1
            fi
        done

        # 启动 ffmpeg 录屏（后台，硬件编码降低 CPU 占用，给同时运行的自动化留余量）
        info "浏览器已就绪，开始录屏 → $rec"
        ffmpeg -f avfoundation -i "${screen_idx}:none" -c:v h264_videotoolbox -b:v 8M "$rec" -y 2>/dev/null &
        local ffmpeg_pid=$!
        # 无论后面 playwright 是否失败/脚本被中断，都保证 ffmpeg 被停止，不留孤儿进程
        # kill/wait 在进程已按信号终止时返回非 0，脚本开着 set -e，必须 || true 否则直接整体退出
        trap 'kill "$ffmpeg_pid" 2>/dev/null || true; wait "$ffmpeg_pid" 2>/dev/null || true; rm -f "$ready_flag" "$go_flag"' EXIT INT TERM
        sleep 1  # ffmpeg 从进程启动到真正稳定写帧需要一点时间

        touch "$go_flag"
        info "已发出录屏启动信号，等待自动化流程跑完..."
        pw_exit=0
        wait "$pw_pid" || pw_exit=$?

        # 停止录屏（trap 会兜底，这里主动触发一次以便后续步骤能立刻用到文件）
        kill "$ffmpeg_pid" 2>/dev/null || true
        wait "$ffmpeg_pid" 2>/dev/null || true
        trap - EXIT INT TERM
        rm -f "$ready_flag" "$go_flag"

        # 校验录屏文件完整性（moov atom 是否存在），避免产出损坏文件却没人发现
        if [ -f "$rec" ]; then
            if ! ffprobe -v error "$rec" 2>&1 | grep -qi "moov atom not found"; then
                ok "录屏文件完整性校验通过"
            else
                err "录屏文件损坏（moov atom 缺失），请重新录制: $rec"
            fi
        fi
        [ "$pw_exit" -ne 0 ] && warn "Playwright 脚本以非 0 状态退出（exit=$pw_exit），请检查录制内容是否完整"

        # timeline.json → subtitles.srt
        if [ -f "$dir/timeline.json" ]; then
            local srt="$dir/subtitles.srt"
            python3 -c "
import json
tl = json.load(open('$dir/timeline.json'))
lines = []
# 跟 srt_to_dub_core 里那份 POLYPHONE_FIXES 保持同步——字幕文本和配音文本必须一致，
# 不然观众会看到字幕写'命令行工具'、听到配音读的是'命令行'，两边对不上
POLYPHONE_FIXES = {
    '命令行工具': '命令行',
}

# 字幕太长一行会顶到屏幕两边（实测 font_size 44 下 55 字左右的整句会跑满 1920px 宽），
# 超过阈值就在中点附近找标点断行；没有合适标点就按视觉宽度（中文/全角标点算 2，其余算 1）
# 切在正中间。断行只影响字幕显示——配音那边 srt_to_dub_core 会把 \n 换成空格拼回一整句读，
# 不会因为断行多停顿。
def visual_width(s):
    w = 0
    for ch in s:
        code = ord(ch)
        if (0x4E00 <= code <= 0x9FFF) or (0x3000 <= code <= 0x303F) or (0xFF00 <= code <= 0xFFEF):
            w += 2
        else:
            w += 1
    return w

def wrap_line(text, max_width=70):
    if visual_width(text) <= max_width:
        return text
    mid = len(text) // 2
    punct = '，。！？；、'
    best = None
    for i, ch in enumerate(text):
        if ch in punct and (best is None or abs(i - mid) < abs(best - mid)):
            best = i
    if best is not None:
        return text[:best+1] + '\n' + text[best+1:].lstrip()
    half = visual_width(text) / 2
    w = 0
    for i, ch in enumerate(text):
        w += visual_width(ch)
        if w >= half:
            return text[:i+1] + '\n' + text[i+1:]
    return text

for i, s in enumerate(tl):
    t = s['t']
    next_t = tl[i+1]['t'] if i+1 < len(tl) else t + 5
    t1 = f'{int(t//3600):02d}:{int((t%3600)//60):02d}:{int(t%60):02d},{int((t%1)*1000):03d}'
    t2 = f'{int(next_t//3600):02d}:{int((next_t%3600)//60):02d}:{int(next_t%60):02d},{int((next_t%1)*1000):03d}'
    text = s['text']
    for bad, good in POLYPHONE_FIXES.items():
        text = text.replace(bad, good)
    text = wrap_line(text)
    lines.append(f'{i+1}\n{t1} --> {t2}\n{text}\n')
with open('$srt','w') as f: f.write('\n'.join(lines))
print(f'✅ SRT: {len(lines)} 段')
" 2>/dev/null
            ok "字幕: $srt"
        fi
    else
        # 回退：纯录屏
        local screen_idx=$(detect_recording_screen)
        info "录制屏幕: 序号 $screen_idx（自动识别的内置/主屏）"
        info "录屏 (Ctrl+C 停止) → $rec"
        ffmpeg -f avfoundation -i "${screen_idx}:none" -c:v h264_videotoolbox -b:v 8M "$rec" -y
    fi
    ok "录制完成: $rec"
}

# ── 交互式录制导航路径（供人工走一遍，生成可靠选择器，避免脚本反复猜选择器）──
cmd_codegen() {
    local dir="$1"
    local out="$dir/nav-draft.spec.js"
    local admin="${ADMIN_URL:-https://127.0.0.1:6848}"
    info "启动 Playwright codegen（中文界面，与实际录制一致）→ $admin"
    info "在弹出的窗口里手动走一遍要自动化的操作路径，关闭窗口后自动保存到:"
    info "  $out"
    warn "生成的选择器需要手动搬进对应的 record.spec.js（尤其是 checkbox/button 等文本相关的）"
    npx playwright codegen --ignore-https-errors --lang=zh-CN --output="$out" "$admin"
    [ -f "$out" ] && ok "已生成: $out"
}

# ── 同步 codegen → record.spec.js ──
cmd_sync() {
    local dir="$1"
    local draft="$dir/nav-draft.spec.js"
    [ ! -f "$draft" ] && { err "缺少 $draft，请先运行 vt codegen"; return 1; }
    info "codegen 选择器已生成: $draft"
    info "将该文件内容发给 AI，AI 会将精确选择器同步到 record.spec.js 并更新 timeline.json"
    ok "请将 nav-draft.spec.js 发给 AI 处理"
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
    local accent=$(meta_get "$meta" "cover_accent_color")
    [ -z "$title" ] && { err "meta.json 缺少 title"; return 1; }
    info "生成封面预览: $title"
    gen_title_card "$title" "${subtitle:-}" "${dur:-3}" "$out" "$logo" "$company" "${accent:-#222222}"
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

# ── 手改 subtitles.srt 之后，跳过重录/重新转写，直接重新配音+合成 ──
# 用法: vt redub <feature>（改完字幕文件后跑这个，几十秒就出新的 mp4，不用等 vt record）
cmd_redub() {
    local dir="$1"
    local rec="$dir/recording.mov"
    local srt="$dir/subtitles.srt"
    [ ! -f "$rec" ] && { err "缺少 recording.mov，请先 vt record"; return 1; }
    [ ! -f "$srt" ] && { err "缺少 subtitles.srt"; return 1; }
    info "重新配音+合成: $(basename "$dir")（复用已有的 recording.mov，不重新录制）"
    echo ""
    srt_to_dub "$dir" || return 1
    echo ""
    compose "$dir"
    echo ""
    ok "$(basename "$dir").mp4"
    show_status "$dir"
}

# 把 subtitles.srt 里所有时间戳整体后移 $2 秒，写到 $3
# （带封面的成片正文整体后移了 cover_dur 秒，字幕要跟着后移，否则会提前 cover_dur 秒出现）
shift_srt() {
    local src="$1" offset="$2" out="$3"
    python3 - "$src" "$offset" "$out" << 'PYEOF'
import re, sys
src, offset, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]

def shift(ts):
    h, m, s_ms = ts.split(':')
    s, ms = s_ms.split(',')
    total = int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000 + offset
    total = max(0, total)
    h = int(total // 3600); total -= h * 3600
    m = int(total // 60); total -= m * 60
    s = int(total)
    ms = round((total - s) * 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

with open(src) as f:
    content = f.read()

def repl(m):
    return f"{shift(m.group(1))} --> {shift(m.group(2))}"

content = re.sub(r'(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})', repl, content)
with open(out, 'w') as f:
    f.write(content)
PYEOF
}

# ffmpeg 把 .srt 转 .ass 时，不给 PlayResX/PlayResY 一律写死 384x288（老 SSA 时代的默认值），
# 交给 subtitles 滤镜渲染到 1920x1080 画面时会整体放大约 3.75 倍——FontSize/MarginV 填的数字
# 跟实际画面上的像素完全对不上（实测 FontSize=20 实际渲染出来接近 75px，字幕又大又占地方，
# 长一点的解说词会被顶到 3 行甚至逼近左右边缘）。
# 修法：自己转 .ass，把 PlayResX/PlayResY 改写成视频真实分辨率 1920x1080，Style 行直接写死
# 像素值——这样 FontSize/MarginV 就是所见即所得的真实像素数，不再有隐藏的放大倍数。
# 用法: ass=$(srt_to_sized_ass "$srt" "$meta")
srt_to_sized_ass() {
    local ff="$1" srt="$2" meta="$3"
    local ass="/tmp/_vt_burn_$$_$RANDOM.ass"
    "$ff" -i "$srt" "$ass" -y 2>/dev/null
    python3 -c "
import json, sys
meta, ass = sys.argv[1], sys.argv[2]
m = json.loads(meta)
s = m.get('subtitle_style') or {}
font = s.get('font_name', 'PingFang SC')
size = s.get('font_size', 44)
color = s.get('color', '&H00FFFFFF')
outline = s.get('outline', '&H00000000')
margin_v = s.get('margin_v', 45)
with open(ass) as f:
    content = f.read()
content = content.replace('PlayResX: 384', 'PlayResX: 1920').replace('PlayResY: 288', 'PlayResY: 1080')
import re
style_line = f'Style: Default,{font},{size},{color},{color},{outline},&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,{margin_v},1'
content = re.sub(r'^Style: Default,.*$', style_line, content, flags=re.MULTILINE)
with open(ass, 'w') as f:
    f.write(content)
" "$meta" "$ass"
    echo "$ass"
}

# ── 在已合成好的成片上烧录硬字幕 ──
# 用法: vt burn <feature>（对 xxx.mp4 / xxx-no-cover.mp4 各产出一份 -sub.mp4，原文件不动）
# 样式来自 meta 的 subtitle_style（项目级 meta.json 可统一覆盖，见项目根目录的 meta.json）
# 依赖 ffmpeg-full（标准 ffmpeg 不带 libass，烧不了字幕）: brew install ffmpeg-full
_burn_one() {
    local ff="$1" src="$2" srt="$3" meta="$4"
    local out="${src%.mp4}-sub.mp4"
    info "烧录字幕: $(basename "$src") → $(basename "$out")"
    local ass; ass=$(srt_to_sized_ass "$ff" "$srt" "$meta")
    "$ff" -i "$src" -vf "ass=filename=$ass" \
        -c:v h264_videotoolbox -b:v 5M -c:a copy "$out" -y 2>/dev/null
    rm -f "$ass"
    [ -f "$out" ] && ok "$(basename "$out")" || err "烧录失败: $(basename "$src")"
}

cmd_burn() {
    local dir="$1"
    local base="$dir/$(basename "$dir")"
    local srt="$dir/subtitles.srt"
    local ff="/usr/local/opt/ffmpeg-full/bin/ffmpeg"

    [ ! -f "$srt" ] && { err "缺少 subtitles.srt"; return 1; }
    [ ! -x "$ff" ] && { err "找不到 ffmpeg-full（需要 libass 才能烧字幕），请先: brew install ffmpeg-full"; return 1; }

    local meta=$(load_meta "$dir" 2>/dev/null || echo "{}")
    local any=0

    # dub_offset 会真实挪动配音在时间轴上的位置（compose() 里用 -ss/adelay 实现），
    # 字幕必须跟着同一个方向、同一个量级偏移，否则配音已经提前/延后了，字幕还对着
    # 画面原本的节奏，两者对不上——这是配音偏移功能上线后必须同步的一环，之前漏了。
    local dub_offset=$(meta_get "$meta" "dub_offset")
    dub_offset="${dub_offset:-0}"

    # 不带封面版本：正文从 0 秒开始，只需要叠加 dub_offset
    if [ -f "$base-no-cover.mp4" ]; then
        any=1
        local use_srt="$srt"
        if python3 -c "exit(0 if abs(float('$dub_offset')) > 0.001 else 1)" 2>/dev/null; then
            use_srt="$dir/_burn_shifted_nc.srt"
            shift_srt "$srt" "$dub_offset" "$use_srt"
        fi
        _burn_one "$ff" "$base-no-cover.mp4" "$use_srt" "$meta"
        [ "$use_srt" != "$srt" ] && rm -f "$use_srt"
    fi

    # 带封面版本：正文整体后移了 cover_duration 秒（跟 compose_final 同一套判断逻辑），
    # 再叠加 dub_offset——字幕要跟着一起偏移，否则字幕会提前/延后于对应画面和配音
    if [ -f "$base.mp4" ]; then
        any=1
        local cover=$(meta_get "$meta" "cover")
        local title=$(meta_get "$meta" "title")
        local cover_dur=$(meta_get "$meta" "cover_duration")
        cover_dur="${cover_dur:-3}"
        local total_shift="$dub_offset"
        if { [ "$cover" = "true" ] || [ -n "$title" ]; } || { [ -n "$cover" ] && [ "$cover" != "false" ]; }; then
            total_shift=$(python3 -c "print(float('$cover_dur') + float('$dub_offset'))")
        fi
        local use_srt="$srt"
        if python3 -c "exit(0 if abs(float('$total_shift')) > 0.001 else 1)" 2>/dev/null; then
            use_srt="$dir/_burn_shifted.srt"
            shift_srt "$srt" "$total_shift" "$use_srt"
        fi
        _burn_one "$ff" "$base.mp4" "$use_srt" "$meta"
        [ "$use_srt" != "$srt" ] && rm -f "$use_srt"
    fi

    [ "$any" = "0" ] && { err "找不到 $base.mp4 或 $base-no-cover.mp4，请先 vt compose"; return 1; }
    return 0
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

# ── vt ui：可视化管理台（meta.json 表单编辑、字幕逐条编辑、字体/语音试听、任务面板）──
# 用法: vt ui [feature]          不带参数只打开首页，带参数直接定位到这个 feature
#      vt ui stop               停止正在跑的 vt-ui 服务
#      vt ui status             查看 vt-ui 有没有在跑
cmd_ui() {
    local arg="${1:-}"
    local port="${VT_UI_PORT:-5175}"

    # stop/status 是保留字，不当 feature 名处理——跟 record 改路径不一样，这两个
    # 不需要任何依赖检测/构建，直接查端口就行，放在最前面尽早 return
    if [ "$arg" = "stop" ]; then
        local pid=$(lsof -ti ":$port" -sTCP:LISTEN 2>/dev/null)
        if [ -z "$pid" ]; then
            info "vt-ui 没有在跑（端口 $port 空闲）"
        else
            kill "$pid" 2>/dev/null && ok "已停止 vt-ui（pid $pid，端口 $port）" || err "停止失败，试试手动: kill $pid"
        fi
        return 0
    fi
    if [ "$arg" = "status" ]; then
        local pid=$(lsof -ti ":$port" -sTCP:LISTEN 2>/dev/null)
        if [ -z "$pid" ]; then
            info "vt-ui 没有在跑（端口 $port 空闲），运行 vt ui 启动"
        else
            ok "vt-ui 正在运行 → http://localhost:$port （pid $pid）"
        fi
        return 0
    fi

    local server_dir="$TOOLKIT_DIR/ui-server"
    local client_dir="$TOOLKIT_DIR/ui-client"

    if [ ! -d "$server_dir" ] || [ ! -d "$client_dir" ]; then
        err "vt-ui 还没装（缺 ui-server/ui-client 目录）"
        return 1
    fi

    # package.json 比 node_modules 新（新增/改过依赖）就重装一次，不能只看 node_modules 存不存在——
    # 之前吃过这个亏：装完 marked 之后没重新 npm install，装机版直接 build 报错找不到模块
    _vt_ui_deps_stale() {
        [ ! -d "$1/node_modules" ] && return 0
        [ "$1/package.json" -nt "$1/node_modules" ] && return 0
        return 1
    }
    if _vt_ui_deps_stale "$client_dir"; then
        info "安装/更新前端依赖…"
        (cd "$client_dir" && npm install) || { err "前端依赖安装失败"; return 1; }
    fi
    if _vt_ui_deps_stale "$server_dir"; then
        info "安装/更新后端依赖…"
        (cd "$server_dir" && npm install) || { err "后端依赖安装失败"; return 1; }
    fi

    # 前端没 build 过，或者源码/依赖比上次 build 新，重新 build 一次
    local need_build=0
    [ ! -d "$client_dir/dist" ] && need_build=1
    if [ -d "$client_dir/dist" ]; then
        [ -n "$(find "$client_dir/src" -newer "$client_dir/dist/index.html" 2>/dev/null)" ] && need_build=1
        [ "$client_dir/package.json" -nt "$client_dir/dist/index.html" ] && need_build=1
    fi
    if [ "$need_build" = "1" ]; then
        info "构建 vt-ui 前端…"
        (cd "$client_dir" && npm run build) || { err "前端构建失败"; return 1; }
    fi

    # 端口已经在跑就直接复用，不重复起进程
    if ! lsof -i ":$port" -sTCP:LISTEN >/dev/null 2>&1; then
        info "启动 vt-ui-server → http://localhost:$port"
        # toolkit 装在哪（~/.local/share/video-toolkit）跟视频项目目录在哪（Videos/xxx）
        # 是两回事，不能让 server 自己瞎猜——用当前工作目录（约定就是在项目目录下跑 vt ui）
        # 的上一级，显式告诉它去哪找 project
        local videos_root="$(cd "$BASE/.." && pwd)"
        (cd "$server_dir" && VT_UI_VIDEOS_ROOT="$videos_root" nohup node index.js > /tmp/vt-ui-server.log 2>&1 &)
        sleep 1
    fi

    local url="http://localhost:$port/"
    if [ -n "$arg" ]; then
        local dir=$(resolve_dir "$arg")
        if [ -n "$dir" ]; then
            local project=$(basename "$(dirname "$dir")")
            local feature=$(basename "$dir")
            url="http://localhost:$port/?project=$project&feature=$feature"
        else
            warn "找不到 feature: $arg，先打开首页"
        fi
    elif ls "$BASE"/feature-* >/dev/null 2>&1; then
        # 没传 feature 参数时，默认用当前目录所在的项目（约定：在项目目录下跑 vt ui）——
        # 不然浏览器端只能靠 localStorage 记的上次选择，或者项目列表里排第一个的，
        # 跟你实际 cd 进来的项目对不上（比如切了个新项目结果打开的还是上次那个/字母序第一个）
        url="http://localhost:$port/?project=$(basename "$BASE")"
    fi
    ok "$url"
    open "$url" 2>/dev/null
}

# ==================== 入口 ====================
case "${1:-}" in
    all)    dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_all "$dir" ;;
    srt)    dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_srt "$dir" ;;
    dub)    dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_dub "$dir" ;;
    redub)  dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_redub "$dir" ;;
    burn)   dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_burn "$dir" ;;
    mix)    dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_mix "$dir" ;;
    recut)
        if [ "${2:-}" = "restore" ]; then
            dir=$(resolve_dir "${3:-}"); [ -z "$dir" ] && { err "找不到 feature: $3"; exit 1; }
            cmd_recut_restore "$dir"
        else
            dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }
            cmd_recut "$dir"
        fi
        ;;
    group-merge) cmd_group_merge "${2:-}" ;;
    cover)  dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_cover "$dir" ;;
    record) dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_record "$dir" ;;
    codegen) dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_codegen "$dir" ;;
    sync)    dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_sync "$dir" ;;
    trans)  dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_trans "$dir" ;;
    en)     dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_en "$dir" ;;
    dub-en) dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_dub_en "$dir" ;;
    mix-en) dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_mix_en "$dir" ;;
    slide)  dir=$(resolve_dir "${2:-}"); [ -z "$dir" ] && { err "找不到 feature: $2"; exit 1; }; cmd_slide_v2 "$dir" ;;
    ui)     cmd_ui "${2:-}" ;;
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
        echo "  vt recut   <feature>    按 cuts.json 剪掉成片里的时间区间（先备份再覆盖）"
        echo "  vt recut   restore <feature>   撤销上一次 recut，恢复剪辑前的版本"
        echo ""
        echo "  vt group-merge <group-id>   按项目 meta.json 里 groups 定义的顺序合并成片，输出到 groups/<id>.mp4"
        echo ""
        echo "  vt slide   <feature>    幻灯片模式 (截图+解说→视频)"
        echo ""
        echo "  vt trans   <feature>    翻译字幕: 中文→英文 (DeepSeek)"
        echo "  vt en      <feature>    英文全流程"
        echo "  vt dub-en  <feature>    仅生成英文配音"
        echo "  vt mix-en  <feature>    仅合成英文视频"
        echo ""
        echo "  vt play    <feature> <dub|dub-en|final|final-en>"
        echo "  vt ui      [feature]    打开可视化管理台"
        echo "  vt ui      stop         停止 vt-ui 服务"
        echo "  vt ui      status       查看 vt-ui 有没有在跑"
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
