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

  # 全部在 Python 中完成：配音 + 合成 + 拼接
  python3 -c "
import json, os, subprocess, tempfile

slide_dir = '$slide_dir'
out_mp4 = '$out'
pages_json = open('$tmp/_pages.json').read()
pages = json.loads(pages_json)
voice = '$default_voice'
edge = '$EDGE'
padding = float('$page_padding' or 1.5)
total = len(pages)
clips = []

for i, p in enumerate(pages):
    num = i + 1
    img = p.get('image','')
    txt = p.get('text') or ''
    v = p.get('voice') or voice
    pd = p.get('duration') or ''
    pp = p.get('page_padding') or padding
    
    # 解说回退
    if not txt:
        # 1. 配对文件
        base = os.path.splitext(img)[0]
        paired = os.path.join(slide_dir, base + '.txt')
        if os.path.exists(paired):
            with open(paired) as f: txt = f.read().strip()
        else:
            # 2. narration.txt
            nar = os.path.join(slide_dir, 'narration.txt')
            if os.path.exists(nar):
                with open(nar) as f:
                    lines = [l.strip() for l in f if l.strip()]
                if i < len(lines): txt = lines[i]
    
    clip = f'$tmp/page_{num:03d}.mp4'
    
    if txt:
        mp3 = f'$tmp/_speech_{num:03d}.mp3'
        if subprocess.run([edge, '--voice', v, '--text', txt, '--write-media', mp3],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0 and os.path.exists(mp3):
            r = subprocess.run(['ffprobe','-v','quiet','-show_entries','format=duration','-of','csv=p=0',mp3],
                             capture_output=True, text=True)
            dur = float(r.stdout.strip() or 3) + pp
            print(f'  [{num}/{total}] {img} (编码中...)\r', end='', flush=True)
            subprocess.run(['ffmpeg','-loop','1','-i',os.path.join(slide_dir,img),
                          '-i',mp3,'-c:v','h264_videotoolbox','-b:v','5M','-r','30',
                          '-c:a','aac','-t',str(dur),'-pix_fmt','yuv420p',clip,'-y'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            os.remove(mp3)
        else:
            print(f'  [{num}/{total}] {img} (配音失败)\r', end='', flush=True)
            subprocess.run(['ffmpeg','-loop','1','-i',os.path.join(slide_dir,img),
                          '-c:v','h264_videotoolbox','-b:v','5M','-r','30',
                          '-t',str(pd or 3),'-pix_fmt','yuv420p','-an',clip,'-y'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        print(f'  [{num}/{total}] {img} (静默)\r', end='', flush=True)
        subprocess.run(['ffmpeg','-loop','1','-i',os.path.join(slide_dir,img),
                      '-c:v','h264_videotoolbox','-b:v','5M','-r','30',
                      '-t',str(pd or 3),'-pix_fmt','yuv420p','-an',clip,'-y'],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    clips.append(clip)
    preview = (txt[:30] + '...') if len(txt) > 30 else (txt or '...')
    print(f'  [{num}/{total}] {img} ({preview})', flush=True)

# 拼接
concat = f'$tmp/concat.txt'
with open(concat, 'w') as f:
    for c in clips:
        f.write(f\"file '{c}'\n\")
subprocess.run(['ffmpeg','-f','concat','-safe','0','-i',concat,'-c','copy',out_mp4,'-y'],
              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print('  ✅ slides.mp4')
"

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
