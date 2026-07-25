#!/bin/bash
# ============================================================
# 录屏后处理 — 语音→字幕→AI配音 全自动流水线
# ============================================================
# 用法:
#   ./post-process.sh <录屏.mp4> [选项]
#
# 工作流:
#   录屏.mp4（用户原声讲解+操作画面）
#     → 提取音频
#     → Whisper 语音识别 → 时间戳 + 文字 → subtitles.srt
#     → 逐句生成 AI 配音（Tingting）
#     → ffmpeg 合成：原视频 + AI配音 + 烧录字幕 → 成片.mp4
#
# 优势: 时间戳从你的语音中提取，AI配音与画面天然同步！
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOICE="Tingting"

# ==================== 依赖检查与安装 ====================
check_deps() {
    local missing=""
    
    # ffmpeg
    if ! command -v ffmpeg &>/dev/null; then
        echo "⚠ ffmpeg 未安装，尝试安装..."
        if command -v brew &>/dev/null; then
            brew install ffmpeg || missing="$missing ffmpeg"
        elif command -v conda &>/dev/null; then
            conda install -y -c conda-forge ffmpeg || missing="$missing ffmpeg"
        else
            missing="$missing ffmpeg"
        fi
    fi
    
    # whisper（优先 faster-whisper，更快更省内存，回退 openai-whisper）
    python3 -c "from faster_whisper import WhisperModel; print('✅ faster-whisper')" 2>/dev/null || \
    python3 -c "import whisper; print('✅ openai-whisper')" 2>/dev/null || {
        echo "⚠ Whisper 未安装，尝试安装 faster-whisper..."
        pip3 install faster-whisper 2>/dev/null || pip3 install openai-whisper 2>/dev/null || missing="$missing whisper"
    }
    
    if [ -n "$missing" ]; then
        echo ""
        echo "========================================="
        echo "  以下工具未能自动安装，请手动安装："
        echo "  $missing"
        echo ""
        echo "  ffmpeg:  brew install ffmpeg"
        echo "  whisper: pip3 install faster-whisper"
        echo "========================================="
        exit 1
    fi
    
    echo "✅ 所有依赖就绪"
}

# ==================== 主流程 ====================
post_process() {
    local input="$1"
    local basename=$(basename "$input")
    basename="${basename%.*}"
    local dir=$(dirname "$input")
    
    # 所有产出物放在视频同目录下
    local dub_audio="$dir/ai_dub.wav"
    local srt_file="$dir/subtitles.srt"
    local final_video="$dir/${basename}_final.mp4"
    local audio_wav="$dir/_audio_tmp.wav"
    local segments_json="$dir/_segments.json"
    
    echo "============================================"
    echo "  后处理: $basename"
    echo "  输出目录: $dir"
    echo "============================================"
    
    # --- Step 1: 提取音频 ---
    echo ""
    echo "━━━ Step 1/5: 提取音频 ━━━"
    ffmpeg -i "$input" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$dir/audio.wav" -y 2>/dev/null
    echo "  → $dir/audio.wav"
    
    # --- Step 2: Whisper 语音识别 → SRT + 逐段时间戳 ---
    echo ""
    echo "━━━ Step 2/5: Whisper 语音识别（需要 1-3 分钟）━━━"
    python3 - "$dir/audio.wav" "$work" << 'PYEOF'
import sys, json, os
audio_file = sys.argv[1]
out_dir = sys.argv[2]

# 优先用 faster-whisper（更快更省内存），回退到 openai-whisper
try:
    from faster_whisper import WhisperModel
    model = WhisperModel("small", device="cpu", compute_type="int8")
    segments_raw, _ = model.transcribe(audio_file, language="zh")
    segments = []
    for seg in segments_raw:
        segments.append({
            "start": seg.start,
            "end": seg.end,
            "text": seg.text.strip()
        })
    print("  [使用 faster-whisper]")
except ImportError:
    import whisper
    model = whisper.load_model("small")
    result = model.transcribe(audio_file, language="zh", verbose=False)
    segments = []
    for seg in result["segments"]:
        segments.append({
            "start": seg["start"],
            "end": seg["end"],
            "text": seg["text"].strip()
        })
    print("  [使用 openai-whisper]")
with open(f"{out_dir}/segments.json", "w") as f:
    json.dump(segments, f, ensure_ascii=False, indent=2)

# 生成 SRT 字幕
with open(f"{out_dir}/subtitles.srt", "w") as f:
    for i, seg in enumerate(segments, 1):
        start = seg["start"]
        end = seg["end"]
        text = seg["text"]
        
        def fmt(t):
            h = int(t // 3600)
            m = int((t % 3600) // 60)
            s = int(t % 60)
            ms = int((t % 1) * 1000)
            return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"
        
        f.write(f"{i}\n")
        f.write(f"{fmt(start)} --> {fmt(end)}\n")
        f.write(f"{text}\n\n")

print(f"  识别完成: {len(segments)} 个片段")
print(f"  → {out_dir}/subtitles.srt")
print(f"  → {out_dir}/segments.json")
print(f"  → {out_dir}/full_text.txt")
PYEOF
    
    # --- Step 3: 逐句生成 AI 配音（macOS say） ---
    echo ""
    echo "━━━ Step 3/5: 生成 AI 配音 ━━━"
    python3 - "$dir/segments.json" "$work" "$VOICE" << 'PYEOF'
import sys, json, os, subprocess

seg_file = sys.argv[1]
out_dir = sys.argv[2]
voice = sys.argv[3]

with open(seg_file) as f:
    segments = json.load(f)

audio_dir = f"{out_dir}/ai_audio"
os.makedirs(audio_dir, exist_ok=True)

# 生成每段 AI 配音
for i, seg in enumerate(segments, 1):
    text = seg["text"]
    orig_dur = seg["end"] - seg["start"]
    wav = f"{audio_dir}/seg_{i:03d}.wav"
    
    # 用 say 生成 AIFF，转 WAV
    aiff = f"{out_dir}/_tmp.aiff"
    subprocess.run(["say", "-v", voice, "-o", aiff, text], capture_output=True)
    
    # 获取 AI 配音实际时长
    result = subprocess.run(
        ["afinfo", aiff], capture_output=True, text=True
    )
    ai_dur = 2.0  # 默认
    for line in result.stdout.split('\n'):
        if 'duration:' in line:
            ai_dur = float(line.split(':')[1].strip())
            break
    
    # 如果 AI 配音和原始语音时长差超过 0.5 秒，用 ffmpeg atempo 调整
    if abs(ai_dur - orig_dur) > 0.5 and ai_dur > 0:
        tempo = ai_dur / orig_dur
        # 限制 atempo 范围 (0.5 ~ 2.0)，多级调整
        if tempo > 2.0:
            subprocess.run([
                "ffmpeg", "-i", aiff,
                "-filter:a", f"atempo=2.0,atempo={tempo/2.0}",
                wav, "-y"
            ], capture_output=True)
        elif tempo < 0.5:
            subprocess.run([
                "ffmpeg", "-i", aiff,
                "-filter:a", f"atempo=0.5,atempo={tempo/0.5}",
                wav, "-y"
            ], capture_output=True)
        else:
            subprocess.run([
                "ffmpeg", "-i", aiff,
                "-filter:a", f"atempo={tempo}",
                wav, "-y"
            ], capture_output=True)
    else:
        subprocess.run([
            "ffmpeg", "-i", aiff, wav, "-y"
        ], capture_output=True)
    
    os.remove(aiff)
    print(f"  [{i}/{len(segments)}] {orig_dur:.1f}s → AI {ai_dur:.1f}s | {text[:30]}...")

# 生成静音片段
silence = f"{audio_dir}/silence.wav"
subprocess.run([
    "ffmpeg", "-f", "lavfi", "-i", "anullsrc=r=16000:cl=mono",
    "-t", "0.5", silence, "-y"
], capture_output=True)

# 生成拼接列表
with open(f"{out_dir}/concat.txt", "w") as f:
    for i in range(1, len(segments) + 1):
        f.write(f"file '{audio_dir}/seg_{i:03d}.wav'\n")
        f.write(f"file '{audio_dir}/silence.wav'\n")

# 拼接所有 AI 配音（含段间静音）
concat_wav = f"{out_dir}/ai_dub.wav"
subprocess.run([
    "ffmpeg", "-f", "concat", "-safe", "0",
    "-i", f"{out_dir}/concat.txt",
    "-c", "copy", concat_wav, "-y"
], capture_output=True)

print(f"  → {out_dir}/ai_dub.wav（AI 配音合成完成）")
PYEOF
    
    # --- Step 4: 替换音频轨道 ---
    echo ""
    echo "━━━ Step 4/5: 替换音频为 AI 配音 ━━━"
    ffmpeg -i "$input" -i "$dir/ai_dub.wav" \
        -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 \
        -shortest "$dir/${basename}_ai_dub.mp4" -y 2>/dev/null
    echo "  → $dir/${basename}_ai_dub.mp4"
    
    # --- Step 5: 烧录字幕 ---
    echo ""
    echo "━━━ Step 5/5: 烧录字幕 ━━━"
    ffmpeg -i "$dir/${basename}_ai_dub.mp4" \
        -vf "subtitles=$dir/subtitles.srt:force_style='FontSize=22,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,Outline=2'" \
        -c:a copy "$dir/${basename}_final.mp4" -y 2>/dev/null
    echo "  → $dir/${basename}_final.mp4"
    
    echo ""
    echo "============================================"
    echo "  ✅ 后处理完成！"
    echo "  成片: $dir/${basename}_final.mp4"
    echo "  字幕: $dir/subtitles.srt"
    echo "============================================"
}

# ==================== 仅生成 SRT（轻量模式） ====================
srt_only() {
    local input="$1"
    local basename=$(basename "$input")
    basename="${basename%.*}"
    local dir=$(dirname "$input")
    
    echo "━━━ 提取音频 + Whisper 识别 → SRT ━━━"
    ffmpeg -i "$input" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$dir/audio.wav" -y 2>/dev/null
    
    python3 - "$dir/audio.wav" "$dir" "$basename" << 'PYEOF'
import sys
audio_file = sys.argv[1]
out_dir = sys.argv[2]
basename = sys.argv[3]

# 优先 faster-whisper
try:
    from faster_whisper import WhisperModel
    model = WhisperModel("small", device="cpu", compute_type="int8")
    segments_raw, _ = model.transcribe(audio_file, language="zh")
    segments = [{"start": s.start, "end": s.end, "text": s.text.strip()} for s in segments_raw]
except ImportError:
    import whisper
    model = whisper.load_model("small")
    result = model.transcribe(audio_file, language="zh", verbose=False)
    segments = [{"start": s["start"], "end": s["end"], "text": s["text"].strip()} for s in result["segments"]]

with open(f"{out_dir}/{basename}.srt", "w") as f:
    for i, seg in enumerate(segments, 1):
        def fmt(t):
            h, m = int(t//3600), int((t%3600)//60)
            s, ms = int(t%60), int((t%1)*1000)
            return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"
        f.write(f"{i}\n{fmt(seg['start'])} --> {fmt(seg['end'])}\n{seg['text']}\n\n")
print(f"  → {out_dir}/{basename}.srt")
PYEOF
    echo "✅ SRT 字幕生成完成"
}

# ==================== 手写 SRT → AI 配音 ====================
srt_to_dub() {
    local srt="$1"
    local video="$2"
    local basename=$(basename "$video")
    basename="${basename%.*}"
    local dir=$(dirname "$video")
    
    echo "从手工 SRT 生成 AI 配音..."
    
    python3 - "$srt" "$dir/$basename" "$VOICE" << 'PYEOF'
import sys, re, os, subprocess

srt_file = sys.argv[1]
out_prefix = sys.argv[2]
voice = sys.argv[3]

# 解析 SRT
with open(srt_file) as f:
    content = f.read()

pattern = r'(\d+)\n(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})\n(.+?)(?=\n\n|\Z)'
matches = re.findall(pattern, content, re.DOTALL)

audio_dir = f"{out_prefix}_dub"
os.makedirs(audio_dir, exist_ok=True)

with open(f"{audio_dir}/concat.txt", "w") as cl:
    for m in matches:
        idx, t1, t2, text = m
        text = text.strip().replace('\n', ' ')
        seg_num = int(idx)
        
        wav = f"{audio_dir}/seg_{seg_num:03d}.wav"
        aiff = "/tmp/_tts.aiff"
        subprocess.run(["say", "-v", voice, "-o", aiff, text], capture_output=True)
        subprocess.run(["ffmpeg", "-i", aiff, wav, "-y"], capture_output=True)
        os.remove(aiff)
        
        # 计算目标时长（从 SRT 时间戳）
        def to_sec(t):
            h, m, s = t.split(':')
            s, ms = s.split(',')
            return int(h)*3600 + int(m)*60 + int(s) + int(ms)/1000
        
        orig_dur = to_sec(t2) - to_sec(t1)
        result = subprocess.run(["afinfo", wav], capture_output=True, text=True)
        ai_dur = 2.0
        for line in result.stdout.split('\n'):
            if 'duration:' in line:
                ai_dur = float(line.split(':')[1].strip())
                break
        
        if abs(ai_dur - orig_dur) > 0.5 and ai_dur > 0:
            tempo = ai_dur / orig_dur
            tmp = "/tmp/_adj.wav"
            subprocess.run(["ffmpeg", "-i", wav, "-filter:a", f"atempo={min(max(tempo,0.5),2.0)}", tmp, "-y"], capture_output=True)
            subprocess.run(["mv", tmp, wav])
        
        cl.write(f"file '{wav}'\n")
        print(f"  [{seg_num}/{len(matches)}] {text[:30]}...")

# 拼接
concat_wav = f"{out_prefix}_ai_dub.wav"
subprocess.run(["ffmpeg", "-f", "concat", "-safe", "0", "-i", f"{audio_dir}/concat.txt", "-c", "copy", concat_wav, "-y"], capture_output=True)
print(f"  → {concat_wav}")
PYEOF
    echo "✅ AI 配音生成完成"
}

# ==================== 入口 ====================
case "${1:-}" in
    srt)
        # 仅生成 SRT（快速模式，不需要 TTS）
        check_deps
        srt_only "$2"
        ;;
    srt2dub)
        # 从手写 SRT 生成 AI 配音
        srt_to_dub "$2" "$3"
        ;;
    "")
        echo "录屏后处理流水线"
        echo ""
        echo "用法:"
        echo "  $0 <录屏.mp4>         完整流程：识别→字幕→AI配音→合成"
        echo "  $0 srt <录屏.mp4>     仅生成 SRT 字幕（快速）"
        echo "  $0 srt2dub <字幕.srt> <视频.mp4>  从手写SRT生成AI配音"
        echo ""
        echo "工作流:"
        echo "  你讲解+录屏 → 脚本提取语音→识别→SRT字幕→AI配音→成片"
        ;;
    *)
        check_deps
        post_process "$1"
        ;;
esac
