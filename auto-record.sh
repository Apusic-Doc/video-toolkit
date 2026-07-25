#!/bin/bash
# ============================================================
# 录屏自动化工具箱
# ============================================================
# 用法:
#   ./generate-audio.sh <feature-dir>          生成 AI 配音
#   ./generate-srt.sh <feature-dir>            生成字幕文件
#   ./auto-prep.sh <feature-dir>               一键生成配音+字幕
#   ./say-list.sh                             列出可用中文语音
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- 可配置项 ----
VOICE="Tingting"        # 中文女声，可选: Tingting(婷婷), Eddy, Flo, Shelley, Reed, Rocko
AUDIO_FORMAT="m4a"      # m4a 或 aiff
CHAR_PER_SEC=4          # 中文 TTS 语速：每秒约 4 个字
# ============================================================

say_list() {
    echo "可用的中文 TTS 语音："
    echo "=============================="
    say -v '?' | grep -E 'zh_CN|zh_TW|zh_HK'
    echo ""
    echo "推荐: Tingting (婷婷，标准女声)"
}

# 从 README.md 提取配音文本
extract_script() {
    local dir="$1"
    local readme="$dir/README.md"
    if [ ! -f "$readme" ]; then
        echo "[ERROR] 找不到 $readme" >&2
        exit 1
    fi
    # 提取 "## 字幕 / 配音稿" 之后的内容，跳过分隔线和空行
    awk '/^## 字幕.*配音稿/{found=1; next}
         found && /^==+/{next}
         found && /^$/{next}
         found && /^##/{exit}
         found' "$readme" \
        | tr '\n' ' ' \
        | sed 's/  */ /g' \
        | xargs
}

# 生成 AI 配音音频
generate_audio() {
    local dir="$1"
    local name=$(basename "$dir")
    local script_text=$(extract_script "$dir")
    
    if [ -z "$script_text" ]; then
        echo "[ERROR] 未找到配音文本，请确认 README.md 中有 '## 字幕 / 配音稿' 段落" >&2
        exit 1
    fi
    
    local outfile="$dir/audio.$AUDIO_FORMAT"
    echo "[生成配音] $name"
    echo "  文本预览: ${script_text:0:60}..."
    echo "  语音: $VOICE"
    
    # macOS say 输出 aiff，再转 m4a
    if [ "$AUDIO_FORMAT" = "m4a" ]; then
        say -v "$VOICE" -o "$dir/_tmp.aiff" "$script_text"
        afconvert -f m4af -d aac "$dir/_tmp.aiff" -o "$outfile" 2>/dev/null \
            || mv "$dir/_tmp.aiff" "$dir/audio.aiff"
        rm -f "$dir/_tmp.aiff"
    else
        say -v "$VOICE" -o "$outfile" "$script_text"
    fi
    
    # 获取时长
    local duration=$(afinfo "$outfile" 2>/dev/null | grep "duration:" | awk '{printf "%.0f", $2}' || echo "?")
    echo "  输出: $outfile"
    echo "  时长: ${duration}秒"
    echo ""
}

# 生成 SRT 字幕（基于文本字数和估算语速）
generate_srt() {
    local dir="$1"
    local name=$(basename "$dir")
    local readme="$dir/README.md"
    local srt="$dir/subtitles.srt"
    
    # 提取配音文本，按句号/感叹号/问号分句
    local raw_text=$(awk '/^## 字幕.*配音稿/{found=1; next}
         found && /^==+/{next}
         found && /^$/{next}
         found && /^##/{exit}
         found' "$readme" \
        | tr '\n' ' ' \
        | sed 's/  */ /g' \
        | xargs)
    
    # 按中文标点分句
    local sentences=$(echo "$raw_text" | sed 's/[。！？；]/&\n/g')
    
    echo "[生成字幕] $name"
    
    local index=1
    local start=0
    
    > "$srt"  # 清空文件
    
    echo "$sentences" | while IFS= read -r sent; do
        sent=$(echo "$sent" | xargs)
        [ -z "$sent" ] && continue
        
        local char_count=${#sent}
        local duration=$(( (char_count / CHAR_PER_SEC) + 1 ))
        ((duration < 2)) && duration=2
        local end=$((start + duration))
        
        # 转时间戳格式 HH:MM:SS,mmm
        local t1=$(printf "%02d:%02d:%02d,000" $((start/3600)) $(((start%3600)/60)) $((start%60)))
        local t2=$(printf "%02d:%02d:%02d,000" $((end/3600)) $(((end%3600)/60)) $((end%60)))
        
        echo "$index" >> "$srt"
        echo "$t1 --> $t2" >> "$srt"
        echo "$sent" >> "$srt"
        echo "" >> "$srt"
        
        ((index++))
        start=$end
    done
    local count=$(grep -c '^[0-9]' "$srt" 2>/dev/null || echo "?")
    echo "  输出: $srt (${count} 条字幕)"
    echo ""
}

# 一键准备（配音 + 字幕）
auto_prep() {
    local dir="$1"
    echo "============================================"
    echo "  一键准备: $(basename "$dir")"
    echo "============================================"
    generate_audio "$dir"
    generate_srt "$dir"
    echo "✅ 准备完成！"
    echo ""
    echo "📋 录制流程："
    echo "  1. 播放 audio.m4a 收听配音（熟悉节奏）"
    echo "  2. 打开 OBS 准备录屏"
    echo "  3. 播放 audio.m4a，同步执行 script.sh 中的命令"
    echo "  4. 后期用 ffmpeg 合成："
    echo "     ffmpeg -i 录屏.mp4 -i audio.m4a -c:v copy -c:a aac 成片.mp4"
    echo "  5. 烧录字幕（可选）："
    echo "     ffmpeg -i 成片.mp4 -vf subtitles=subtitles.srt 最终.mp4"
}

# 批量生成所有 feature
batch_all() {
    local base="$SCRIPT_DIR/.."
    for dir in "$base"/feature-*/; do
        auto_prep "$dir"
    done
}

# ==================== 入口 ====================
case "${1:-}" in
    audio)    generate_audio "$2" ;;
    srt)      generate_srt "$2" ;;
    prep)     auto_prep "$2" ;;
    batch)    batch_all ;;
    voices)   say_list ;;
    *)
        echo "录屏自动化工具箱"
        echo ""
        echo "用法:"
        echo "  $0 prep   <feature-dir>    一键生成配音+字幕"
        echo "  $0 audio  <feature-dir>    仅生成 AI 配音"
        echo "  $0 srt    <feature-dir>    仅生成 SRT 字幕"
        echo "  $0 batch                   批量处理所有 feature"
        echo "  $0 voices                  列出可用中文语音"
        echo ""
        echo "示例:"
        echo "  $0 prep ../feature-05-cli-offline-config"
        ;;
esac
