#!/bin/bash
# ============================================================
# 幻灯片系统 — build_pages + 解说回退 + 内容段生成
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDGE="${EDGE_TTS:-$SCRIPT_DIR/.venv/bin/edge-tts}"
[ -x "$EDGE" ] || EDGE="edge-tts"
type warn 2>/dev/null | grep -q function || warn() { echo -e "  ⚠  $1"; }

build_pages() {
  local dir="$1"; local meta="$2"
  python3 -c "
import json, os
meta = json.loads('''$meta''')
pages = meta.get('slides',{}).get('pages',[])
if not pages:
    d=os.path.join('$dir','slides')
    if os.path.isdir(d):
        files=sorted([f for f in os.listdir(d) if f.endswith(('.png','.jpg','.jpeg'))])
        pages=[{'image':f} for f in files]
dv=meta.get('voice','zh-CN-XiaoxiaoNeural')
for p in pages:
    p.setdefault('voice',None)
    if not p.get('voice'): p['voice']=dv
    p.setdefault('text',None)
    p.setdefault('duration',None)
    p.setdefault('page_padding',None)
    p.setdefault('transition',None)
    p.setdefault('zoom',None)
print(json.dumps(pages))
"
}

get_narration() {
  local slide_dir="$1" image="$2" idx="$3"
  local base="${image%.*}"
  [ -f "$slide_dir/${base}.txt" ] && { cat "$slide_dir/${base}.txt"; return; }
  if [ -f "$slide_dir/narration.txt" ]; then
    local line=$(sed -n "$((idx+1))p" "$slide_dir/narration.txt" 2>/dev/null)
    [ -n "$line" ] && { echo "$line"; return; }
  fi
  echo ""
}

gen_slide_video() {
  local pages="$1"; local meta="$2"; local dir="$3"; local out="$4"
  local slide_dir="$dir/slides"
  local tmp="/tmp/_vt_slide_$$"
  rm -rf "$tmp"; mkdir -p "$tmp"
  local page_padding=$(meta_get "$meta" "slides.page_padding")
  local default_voice=$(meta_get "$meta" "voice")
  local count=$(python3 -c "import json;print(len(json.loads('''$pages''')))")

  python3 -c "
import json
pages=json.loads('''$pages''')
for p in pages:
    print(p.get('image','')+'\x1f'+(p.get('text')or'')+'\x1f'+(p.get('voice')or'')+'\x1f'+(p.get('duration')or'')+'\x1f'+(p.get('page_padding')or''))
" > "$tmp/_pages.txt"

  local i=0
  while IFS=$'\x1f' read -r image text voice pd pp; do
    local num=$((i+1))
    local clip="$tmp/page_$(printf '%03d' $num).mp4"
    [ -z "$text" ] || [ "$text" = "None" ] && text=$(get_narration "$slide_dir" "$image" "$i")
    [ -z "$voice" ] || [ "$voice" = "None" ] && voice="$default_voice"

    if [ -n "$text" ] && [ "$text" != "None" ]; then
      local mp3="$tmp/_speech_$(printf '%03d' $num).mp3"
      if [ "${DEBUG:-0}" = "1" ]; then "$EDGE" --voice "$voice" --text "$text" --write-media "$mp3"
      else "$EDGE" --voice "$voice" --text "$text" --write-media "$mp3" 2>/dev/null; fi

      if [ -f "$mp3" ]; then
        local speech_dur=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$mp3" 2>/dev/null || echo 3)
        local total_dur=$(python3 -c "print($speech_dur + ${pp:-1.5})")
        echo -ne "  [$num/$count] $image 编码中...\r"
        ffmpeg -loop 1 -i "$slide_dir/$image" -i "$mp3" \
          -c:v h264_videotoolbox -b:v 5M -r 30 -c:a aac \
          -t "$total_dur" -pix_fmt yuv420p "$clip" -y 2>/dev/null
        rm -f "$mp3"
      else
        if [ "${DEBUG:-0}" = "1" ]; then warn "edge-tts 失败"; else warn "配音失败: $image 使用静默"; fi
        ffmpeg -loop 1 -i "$slide_dir/$image" \
          -c:v h264_videotoolbox -b:v 5M -r 30 \
          -t "${pd:-3}" -pix_fmt yuv420p -an "$clip" -y 2>/dev/null
      fi
    else
      ffmpeg -loop 1 -i "$slide_dir/$image" \
        -c:v h264_videotoolbox -b:v 5M -r 30 \
        -t "${pd:-3}" -pix_fmt yuv420p -an "$clip" -y 2>/dev/null
    fi

    local preview="${text:0:30}"
    [ ${#text} -gt 30 ] && preview="${preview}..."
    echo -e "\r  [$num/$count] $image ($preview)    "
    ((i++))
  done < "$tmp/_pages.txt"

  local concat="$tmp/concat.txt"; > "$concat"
  for c in "$tmp"/page_*.mp4; do echo "file '$c'" >> "$concat"; done
  ffmpeg -f concat -safe 0 -i "$concat" -c copy "$out" -y 2>/dev/null
  rm -rf "$tmp"
  echo "  ✅ slides.mp4"
}

build_subtitle() {
  local dir="$1"; local meta="$2"; local out="$3"
  local mode=$(meta_get "$meta" "subtitle.mode")
  case "$mode" in
    null|None) return ;;
    paired)
      local pages=$(build_pages "$dir" "$meta")
      local slide_dir="$dir/slides"
      local page_padding=$(meta_get "$meta" "slides.page_padding")
      local count=$(python3 -c "import json;print(len(json.loads('''$pages''')))")
      local time=0.0
      > "$out"
      for i in $(seq 0 $((count-1))); do
        local num=$((i+1))
        local image=$(python3 -c "import json;print(json.loads('''$pages''')[$i]['image'])")
        local text=$(python3 -c "import json;print(json.loads('''$pages''')[$i].get('text')or'')")
        [ -z "$text" ] || [ "$text" = "None" ] && text=$(get_narration "$slide_dir" "$image" "$i")
        [ -z "$text" ] || [ "$text" = "None" ] && continue
        local chars=${#text}
        local dur=$(python3 -c "print(max($chars/4,2)+${page_padding:-1.5})")
        local end=$(python3 -c "print($time+$dur)")
        printf "%d\n%02d:%02d:%02d,%03d --> %02d:%02d:%02d,%03d\n%s\n\n" $num \
          $(python3 -c "print(int($time//3600),int(($time%3600)//60),int($time%60),int(($time%1)*1000))") \
          $(python3 -c "print(int($end//3600),int(($end%3600)//60),int($end%60),int(($end%1)*1000))") \
          "$text" >> "$out"
        time=$end
      done
      echo "  ✅ 字幕已生成"
      ;;
    *) [ -f "$dir/subtitles.srt" ] && cp "$dir/subtitles.srt" "$out" 2>/dev/null ;;
  esac
}
