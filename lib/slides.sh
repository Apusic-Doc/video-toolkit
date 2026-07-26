#!/bin/bash
# ============================================================
# 幻灯片系统 — build_pages + 解说回退 + 内容段生成
# ============================================================
# 用法: source lib/slides.sh (需先 source lib/meta.sh)
#       pages=$(build_pages "$feature_dir" "$meta")
#       gen_slide_video "$pages" "$meta" "$feature_dir" "$output.mp4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDGE="${EDGE_TTS:-$SCRIPT_DIR/.venv/bin/edge-tts}"
[ -x "$EDGE" ] || EDGE="edge-tts"

# ── 构建 pages ──
build_pages() {
  local dir="$1"; local meta="$2"
  python3 -c "
import json, os
meta = json.loads('''$meta''')
pages = meta.get('slides', {}).get('pages', [])
if not pages:
    slide_dir = os.path.join('$dir', 'slides')
    if os.path.isdir(slide_dir):
        files = sorted([f for f in os.listdir(slide_dir) if f.endswith(('.png','.jpg','.jpeg'))])
        pages = [{'image': f} for f in files]
defaults = meta.get('slides', {})
for p in pages:
    p.setdefault('voice', None)
    p.setdefault('text', None)
    p.setdefault('duration', None)
    p.setdefault('page_padding', None)
    p.setdefault('transition', None)
    p.setdefault('zoom', None)
print(json.dumps(pages))
"
}

# ── 解说三级回退 ──
get_narration() {
  local slide_dir="$1" image="$2" idx="$3"
  local base="${image%.*}"
  # 1. 配对文件
  [ -f "$slide_dir/${base}.txt" ] && { cat "$slide_dir/${base}.txt"; return; }
  # 2. narration.txt 按行
  if [ -f "$slide_dir/narration.txt" ]; then
    local line=$(sed -n "$((idx+1))p" "$slide_dir/narration.txt" 2>/dev/null)
    [ -n "$line" ] && { echo "$line"; return; }
  fi
  # 3. 无
  echo ""
}

# ── 生成幻灯片内容视频 ──
gen_slide_video() {
  local pages="$1"; local meta="$2"; local dir="$3"; local out="$4"
  local slide_dir="$dir/slides"
  local tmp="/tmp/_vt_slide_$$"
  mkdir -p "$tmp"
  local clips=()
  local page_padding=$(meta_get "$meta" "slides.page_padding")
  local default_voice=$(meta_get "$meta" "voice")
  local count=$(python3 -c "import json; print(len(json.loads('''$pages''')))")

  for i in $(seq 0 $((count-1))); do
    local num=$((i+1))
    local image=$(python3 -c "import json; print(json.loads('''$pages''')[$i]['image'])")
    local text=$(python3 -c "import json; print(json.loads('''$pages''')[$i].get('text') or '')")
    local voice=$(python3 -c "import json; print(json.loads('''$pages''')[$i].get('voice') or '$default_voice')")
    local pd=$(python3 -c "import json; print(json.loads('''$pages''')[$i].get('duration') or '')")
    local pp=$(python3 -c "import json; print(json.loads('''$pages''')[$i].get('page_padding') or '$page_padding')")
    local clip="$tmp/page_$(printf '%03d' $num).mp4"

    # 三级回退
    if [ -z "$text" ] || [ "$text" = "None" ]; then
      text=$(get_narration "$slide_dir" "$image" "$i")
    fi

    if [ -n "$text" ] && [ "$text" != "None" ]; then
      # 有解说：配音 + 图片
      local mp3="$tmp/_speech_$(printf '%03d' $num).mp3"
      "$EDGE" --voice "$voice" --text "$text" --write-media "$mp3" 2>/dev/null

      local speech_dur=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$mp3" 2>/dev/null || echo 3)
      local total_dur=$(python3 -c "print($speech_dur + ${pp:-1.5})")

      ffmpeg -loop 1 -i "$slide_dir/$image" -i "$mp3" \
        -c:v libx264 -preset ultrafast -crf 23 -c:a aac \
        -t "$total_dur" -pix_fmt yuv420p "$clip" -y 2>/dev/null
      rm -f "$mp3"
    else
      # 无解说：纯图片
      ffmpeg -loop 1 -i "$slide_dir/$image" \
        -c:v libx264 -preset ultrafast -crf 23 \
        -t "${pd:-3}" -pix_fmt yuv420p -an "$clip" -y 2>/dev/null
    fi

    clips+=("$clip")
    echo -e "  [$num/$count] $image ($(python3 -c "print('${text:0:30}')" 2>/dev/null || echo '...'))"
  done

  # 拼接
  local concat="$tmp/concat.txt"
  > "$concat"
  for c in "${clips[@]}"; do echo "file '$c'" >> "$concat"; done
  ffmpeg -f concat -safe 0 -i "$concat" -c copy "$out" -y 2>/dev/null

  rm -rf "$tmp"
  echo "  ✅ slides.mp4"
}
