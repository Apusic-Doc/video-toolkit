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

  # 写 pages JSON 到文件
  python3 -c "
import json
with open('$tmp/_pages.json','w') as f:
    json.dump(json.loads('''$pages'''), f, ensure_ascii=False)
"

  # 全部在 Python 中完成：配音 + 合成 + 拼接
  python3 -c "
import json, os, subprocess, tempfile, time, threading, sys, hashlib

def file_md5(path):
    if not os.path.exists(path): return ''
    with open(path, 'rb') as f:
        return hashlib.md5(f.read()).hexdigest()

def text_hash(text):
    return hashlib.md5(text.encode()).hexdigest()[:8]

spin = '⣾⣽⣻⢿⡿⣟⣯⣷'
def show_spinner(msg, stop_event):
    i = 0
    start = time.time()
    while not stop_event.is_set():
        c = spin[i % 8]
        elapsed = time.time() - start
        print(f'\r  {c} {msg} {elapsed:.0f}s', end='', flush=True)
        time.sleep(0.3)
        i += 1

slide_dir = '$slide_dir'
out_mp4 = '$out'
pages_json = open('$tmp/_pages.json').read()
pages = json.loads(pages_json)
voice = '$default_voice'
edge = '$EDGE'
padding = float('$page_padding' or 1.5)
total = len(pages)
clips = []
force = '${FORCE:-0}' == '1'

# 缓存
cache_file = os.path.join('$dir', '.slide-cache.json')
cache = {}
if not force and os.path.exists(cache_file):
    with open(cache_file) as f:
        cache = json.load(f)

for i, p in enumerate(pages):
    num = i + 1
    img = p.get('image','')
    txt = p.get('text') or ''
    v = p.get('voice') or voice
    pd = p.get('duration') or ''
    pp = p.get('page_padding') or padding
    
    # 解说回退
    if not txt:
        base = os.path.splitext(img)[0]
        paired = os.path.join(slide_dir, base + '.txt')
        if os.path.exists(paired):
            with open(paired) as f: txt = f.read().strip()
        else:
            nar = os.path.join(slide_dir, 'narration.txt')
            if os.path.exists(nar):
                with open(nar) as f:
                    lines = [l.strip() for l in f if l.strip()]
                if i < len(lines): txt = lines[i]
    
    clip = f'$dir/_clips/page_{num:03d}.mp4'

    # 创建输出目录
    os.makedirs(os.path.dirname(clip), exist_ok=True)

    # 图片文件检查
    img_path = os.path.join(slide_dir, img)
    if not os.path.exists(img_path):
        print(f'  ⚠ 图片不存在 [{num}/{total}] {img}', flush=True)
        continue

    # 缓存：图+文未变则跳过
    if force or not os.path.exists(clip):
        pass  # 需要重新生成
    else:
        img_md5 = file_md5(os.path.join(slide_dir, img))
        txt_h = text_hash(txt)
        ck = str(num)
        if ck in cache and cache[ck].get('img_md5') == img_md5 and cache[ck].get('txt_h') == txt_h:
            preview = (txt[:35] + '...') if len(txt) > 35 else txt
            print(f'  ✅ 缓存 [{num}/{total}] {img}  {preview}', flush=True)
            clips.append(clip)
            continue
    
    if txt:
        mp3 = f'$tmp/_speech_{num:03d}.mp3'
        
        # TTS 生成 + 旋转等待
        stop_tts = threading.Event()
        t = threading.Thread(target=show_spinner, args=(f'TTS [{num}/{total}]', stop_tts))
        t.start()
        tts_start = time.time()
        result = subprocess.run([edge, '--voice', v, '--text', txt, '--write-media', mp3],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        tts_elapsed = time.time() - tts_start
        stop_tts.set(); t.join()
        
        if result.returncode == 0 and os.path.exists(mp3):
            r = subprocess.run(['ffprobe','-v','quiet','-show_entries','format=duration','-of','csv=p=0',mp3],
                             capture_output=True, text=True)
            dur = float(r.stdout.strip() or 3) + pp
            
            # 编码 + 旋转等待
            stop_enc = threading.Event()
            t2 = threading.Thread(target=show_spinner, args=(f'[{num}/{total}] {img} 编码', stop_enc))
            t2.start()
            enc_start = time.time()
            subprocess.run(['ffmpeg','-loop','1','-i',os.path.join(slide_dir,img),
                          '-i',mp3,'-vf','scale=1920:-2','-c:v','h264_videotoolbox','-b:v','5M','-r','30',
                          '-c:a','aac','-t',str(dur),'-pix_fmt','yuv420p',clip,'-y'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            enc_elapsed = time.time() - enc_start
            stop_enc.set(); t2.join()
            os.remove(mp3)
            preview = (txt[:35] + '...') if len(txt) > 35 else txt
            print(f'\r  [{num}/{total}] {img} 🎙️{tts_elapsed:.0f}s 🎬{enc_elapsed:.0f}s  {preview}', flush=True)
        else:
            print(f'\r  ⚠ TTS 失败 [{num}/{total}] {img}', flush=True)
            subprocess.run(['ffmpeg','-loop','1','-i',os.path.join(slide_dir,img),
                          '-vf','scale=1920:-2','-c:v','h264_videotoolbox','-b:v','5M','-r','30',
                          '-t',str(pd or 3),'-pix_fmt','yuv420p','-an',clip,'-y'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print(f'  ⚠ TTS 失败 [{num}/{total}] {img}', flush=True)
    else:
        print(f'  [{num}/{total}] {img} (静默)', flush=True)
        subprocess.run(['ffmpeg','-loop','1','-i',os.path.join(slide_dir,img),
                      '-vf','scale=1920:-2','-c:v','h264_videotoolbox','-b:v','5M','-r','30',
                      '-t',str(pd or 3),'-pix_fmt','yuv420p','-an',clip,'-y'],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    clips.append(clip)
    preview = (txt[:30] + '...') if len(txt) > 30 else (txt or '...')
    print(f'  [{num}/{total}] {img} ({preview})', flush=True)

# 构建缓存数据
for i, p in enumerate(pages):
    img = p.get('image','')
    txt = p.get('text') or ''
    if not txt:
        base = os.path.splitext(img)[0]
        paired = os.path.join(slide_dir, base + '.txt')
        if os.path.exists(paired):
            with open(paired) as f: txt = f.read().strip()
        else:
            nar = os.path.join(slide_dir, 'narration.txt')
            if os.path.exists(nar):
                with open(nar) as f:
                    lines = [l.strip() for l in f if l.strip()]
                if i < len(lines): txt = lines[i]
    img_md5 = file_md5(os.path.join(slide_dir, img))
    txt_h = text_hash(txt)
    cache[str(i+1)] = {'img_md5': img_md5, 'txt_h': txt_h}

# 保存缓存
with open(cache_file, 'w') as f:
    json.dump(cache, f, ensure_ascii=False, indent=2)

# 拼接
concat = f'$dir/_clips/concat.txt'
with open(concat, 'w') as f:
    for c in clips:
        f.write(f\"file '{c}'\n\")

# 调试：打印拼接命令
print(f'  拼接 {len(clips)} 个片段:', flush=True)
for c in clips:
    print(f'    {c}', flush=True)
print(f'  ffmpeg -f concat -safe 0 -i {concat} -c:v h264_videotoolbox -b:v 5M -r 30 -c:a aac {out_mp4} -y', flush=True)

subprocess.run(['ffmpeg','-f','concat','-safe','0','-i',concat,'-c:v','h264_videotoolbox','-b:v','5M','-r','30','-c:a','aac',out_mp4,'-y'],
              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
"

  rm -rf "$tmp"
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
