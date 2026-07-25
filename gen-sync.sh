#!/bin/bash
# ============================================================
# 逐步骤配音生成器 — 让配音与操作画面完美同步
# ============================================================
# 用法:
#   ./gen-sync.sh <feature-dir>   为一个 feature 生成逐步骤配音
#   ./gen-sync.sh all              批量处理全部 18 个 feature
# ============================================================
set -e

VOICE="Tingting"
AUDIO_DIR="audio"
FORMAT="wav"   # wav 格式 Windows 原生支持，也可改 m4a

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="$SCRIPT_DIR/.."

# 列出可用语音
say_voices() {
    echo "可用中文语音："
    say -v '?' | grep -E 'zh_CN|zh_TW'
    echo "当前: $VOICE"
}

# 生成一个 feature
gen_one() {
    local dir="$1"
    local name=$(basename "$dir")
    local script="$dir/script.sh"
    
    if [ ! -f "$script" ]; then
        echo "[SKIP] $name — 无 script.sh"
        return
    fi
    
    # 提取 # @配音: 行
    local audio_lines=$(grep -n '# @配音:' "$script" 2>/dev/null || true)
    if [ -z "$audio_lines" ]; then
        echo "[SKIP] $name — 无 @配音 标记"
        return
    fi
    
    echo "============================================"
    echo "  $name"
    echo "============================================"
    
    # 创建音频目录
    mkdir -p "$dir/$AUDIO_DIR"
    rm -f "$dir/$AUDIO_DIR"/*.wav
    
    # 逐行处理
    local step=1
    local new_script=""
    local last_line=0
    local total_steps=$(echo "$audio_lines" | wc -l | tr -d ' ')
    
    while IFS=':' read -r lineno text; do
        # text 去掉开头的空格和 "# @配音: " 前缀
        text=$(echo "$text" | sed 's/^[[:space:]]*# @配音:[[:space:]]*//')
        [ -z "$text" ] && continue
        
        local audio_file="$AUDIO_DIR/step_$(printf '%02d' $step).$FORMAT"
        echo "  [$step/$total_steps] $text"
        echo "    → $audio_file"
        
        # 生成音频
        say -v "$VOICE" -o "$dir/_tmp.aiff" "$text" 2>/dev/null
        if [ "$FORMAT" = "wav" ]; then
            afconvert -f WAVE -d LEI16 "$dir/_tmp.aiff" -o "$dir/$audio_file" 2>/dev/null
        else
            afconvert -f m4af -d aac "$dir/_tmp.aiff" -o "$dir/$audio_file" 2>/dev/null
        fi
        rm -f "$dir/_tmp.aiff"
        
        ((step++))
    done < <(echo "$audio_lines")
    
    echo "  共生成 $((step-1)) 个音频文件"
    echo ""
    
    # 生成录制用脚本 record.sh（Mac 版）
    cat > "$dir/record.sh" << 'RECHEAD'
#!/bin/bash
# ===== 录制模式：逐步骤播配音 + 执行命令 =====
# 运行此脚本，它会逐段播放配音并执行操作，你只需同步录屏即可
set -e
cd "$(dirname "$0")/../../../aas/bin" || exit 1
alias aas='./asadmin --user admin --passwordfile .asadmin_pass'

echo "============================================"
echo "  录制模式 — 配音与画面自动同步"
echo "  请先启动 OBS 录屏，然后按 Enter 开始"
echo "============================================"
read -p "按 Enter 开始录制..."

RECHEAD
    
    # 读取原始 script.sh 并转换
    local step=1
    while IFS= read -r line; do
        if echo "$line" | grep -q '# @配音:'; then
            local text=$(echo "$line" | sed 's/.*# @配音:[[:space:]]*//')
            local af="$AUDIO_DIR/step_$(printf '%02d' $step).$FORMAT"
            cat >> "$dir/record.sh" << EOF

# === 第 $step 步 ===
echo ""
echo "▶ 配音播放中..."
ffplay -nodisp -autoexit -loglevel quiet "../$af" 2>/dev/null || afplay "../$af" 2>/dev/null || echo "  (播放 $af)"
EOF
            ((step++))
        elif echo "$line" | grep -qE '^(#!/|cd |alias )'; then
            :  # 跳过头部（已在 RECHEAD 中处理）
        else
            echo "$line" >> "$dir/record.sh"
        fi
    done < "$script"
    
    cat >> "$dir/record.sh" << 'RETAIL'

echo ""
echo "============================================"
echo "  录制完成！停止 OBS 录屏。"
echo "============================================"
RETAIL
    
    chmod +x "$dir/record.sh"
    echo "  → 生成 $dir/record.sh（录制用脚本）"
    echo ""
}

# ==================== 入口 ====================
case "${1:-}" in
    all|batch)
        for dir in "$BASE"/feature-*/; do
            gen_one "$dir"
        done
        echo "✅ 全部完成！"
        ;;
    voices)
        say_voices
        ;;
    *)
        if [ -d "$1" ]; then
            gen_one "$1"
        else
            echo "用法:"
            echo "  $0 <feature-dir>   为一个 feature 生成同步配音"
            echo "  $0 all              批量处理全部 18 个 feature"
            echo "  $0 voices           列出可用中文语音"
            echo ""
            echo "示例:"
            echo "  $0 ../feature-05-cli-offline-config"
        fi
        ;;
esac
