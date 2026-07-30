#!/bin/bash
# ============================================================
# compose_final — 通用视频合成器
# ============================================================

# ── 生成标题封面（白屏 + 居中文字 + logo + 公司名）──
# 只生成封面静态图（不转视频）——vt ui 的实时预览和 gen_title_card 共用这一份，
# 避免 magick 拼图逻辑在两个地方各写一遍、以后改一处忘了改另一处
gen_title_card_png() {
  local title="$1" subtitle="$2" out="$3" logo="$4" company="$5" accent="${6:-#222222}"
  [ -z "$title" ] && return 1
  local font=""
  for f in "/System/Library/Fonts/Supplemental/Songti.ttc" \
           "/System/Library/Fonts/STHeiti Medium.ttc" \
           "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc" \
           "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"; do
    [ -f "$f" ] && { font="$f"; break; }
  done
  # 1. 白底 + 标题（默认深灰，meta.cover_accent_color 可覆盖成跟管控台一致的品牌色）+ 副标题
  magick -size 1920x1080 xc:'#FFFFFF' -gravity center \
    ${font:+-font "$font"} \
    -fill "$accent" -pointsize 60 -draw "text 0,-60 '$title'" \
    -fill '#666666' -pointsize 42 -draw "text 0,30 '$subtitle'" \
    "$out" 2>/dev/null || return 1
  # 2. Logo（缩放+叠加，保留原色）
  if [ -n "$logo" ] && [ -f "$logo" ]; then
    local logo_small="/tmp/_vt_logo_$$.png"
    magick "$logo" -resize x80 "$logo_small" 2>/dev/null
    magick "$out" "$logo_small" -geometry +40+30 -composite -colorspace sRGB "$out" 2>/dev/null
    rm -f "$logo_small"
  fi
  # 3. 公司名（底部居中）
  if [ -n "$company" ] && [ -n "$font" ]; then
    magick "$out" -font "$font" -gravity south -fill '#999999' -pointsize 24 \
      -draw "text 0,50 '$company'" -colorspace sRGB "$out" 2>/dev/null
  fi
}

gen_title_card() {
  local title="$1" subtitle="$2" duration="${3:-3}" out="$4"
  local logo="$5" company="$6" accent="${7:-#222222}"
  [ -z "$title" ] && return 1
  local png="/tmp/_vt_cover_$$.png"
  gen_title_card_png "$title" "$subtitle" "$png" "$logo" "$company" "$accent" || return 1
  # 转视频（带静音轨，编码参数与正文对齐以便拼接时 stream-copy）
  ffmpeg -loop 1 -i "$png" -f lavfi -i "anullsrc=r=48000:cl=stereo" \
    -c:v h264_videotoolbox -b:v 5M -r 30 -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black" -pix_fmt yuv420p \
    -t "$duration" -c:a aac -ar 48000 -ac 2 -shortest "$out" -y 2>/dev/null
  rm -f "$png"
}

# ── 生成封面片段（图片或视频） ──
# 编码参数（h264_videotoolbox/30fps/1920x1080/yuv420p/48k stereo aac）与正文对齐，
# 使 compose_final 拼接时可用 -c copy 而非整段重新软编码
gen_cover() {
  local asset="$1" dur="$2" out="$3"
  if [[ "$asset" == *.mp4 || "$asset" == *.mov ]]; then
    ffmpeg -i "$asset" -f lavfi -i "anullsrc=r=48000:cl=stereo" \
      -c:v h264_videotoolbox -b:v 5M -r 30 -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black" -pix_fmt yuv420p \
      -c:a aac -ar 48000 -ac 2 -map 0:v:0 -map 1:a:0 -shortest "$out" -y 2>/dev/null && echo "$out"
  else
    ffmpeg -loop 1 -i "$asset" -f lavfi -i "anullsrc=r=48000:cl=stereo" \
      -c:v h264_videotoolbox -b:v 5M -r 30 -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black" -pix_fmt yuv420p \
      -t "$dur" -c:a aac -ar 48000 -ac 2 -shortest "$out" -y 2>/dev/null && echo "$out"
  fi
}

# ── 生成封底片段 ──
gen_outro() {
  gen_cover "$1" "$2" "$3"
}

# ── 主合成 ──
compose_final() {
  local content="$1" meta="$2" dir="$3" out="$4"
  local tmp="/tmp/_vt_compose_$$"; mkdir -p "$tmp"
  local parts=()

  # ── 1. 标题封面 ──
  local cover=$(resolve_asset "$dir" "$meta" "cover")
  local title=$(meta_get "$meta" "title")
  local subtitle=$(meta_get "$meta" "subtitle")
  local cover_dur=$(meta_get "$meta" "cover_duration")
  
  if [ "$cover" = "true" ] || [ -n "$title" ]; then
    echo "➜ 添加标题封面..."
    local cover_clip="$tmp/cover.mp4"
    local logo=$(resolve_asset "$dir" "$meta" "logo")
    local company=$(meta_get "$meta" "company")
    local accent=$(meta_get "$meta" "cover_accent_color")
    gen_title_card "$title" "${subtitle:-}" "${cover_dur:-3}" "$cover_clip" "$logo" "$company" "${accent:-#222222}" 2>/dev/null
    [ -f "$cover_clip" ] && parts+=("$cover_clip") || echo "⚠  封面生成失败"
  elif [ -n "$cover" ] && [ "$cover" != "false" ]; then
    echo "➜ 添加封面..."
    local cover_clip="$tmp/cover.mp4"
    gen_cover "$cover" "${cover_dur:-3}" "$cover_clip" && parts+=("$cover_clip") || echo "⚠  封面生成失败"
  fi

  # ── 2. 正文内容 ──
  parts+=("$content")

  # ── 3. 封底 ──
  # 跟 BGM 同理：封底会实打实改变成片结构（多出几秒画面），不能因为 resources/
  # 目录里刚好放了个 outro.png（还是个占位用的纯黑图）就默默给所有视频都加上，
  # 必须 meta 显式设成 true 或给具体路径才启用。
  local outro_flag=$(meta_get "$meta" "outro")
  local outro=""
  if [ "$outro_flag" != "false" ] && [ "$outro_flag" != "None" ] && [ "$outro_flag" != "null" ] && [ -n "$outro_flag" ]; then
    outro=$(resolve_asset "$dir" "$meta" "outro")
  fi
  if [ -n "$outro" ] && [ "$outro" != "false" ]; then
    echo "➜ 添加封底..."
    local outro_dur=$(meta_get "$meta" "outro_duration")
    local outro_clip="$tmp/outro.mp4"
    gen_outro "$outro" "${outro_dur:-3}" "$outro_clip" && parts+=("$outro_clip")
  fi

  # ── 4. 拼接 ──
  # 各片段编码参数已在 gen_title_card/gen_cover/正文生成阶段对齐，
  # 直接 stream-copy 拼接，避免整段视频重复软编码
  if [ ${#parts[@]} -eq 1 ]; then
    cp "$content" "$out"
  else
    echo "⏳ 合成 ${#parts[@]} 个片段..."
    local concat="$tmp/concat.txt"
    > "$concat"
    for p in "${parts[@]}"; do echo "file '$p'" >> "$concat"; done
    if ! ffmpeg -f concat -safe 0 -i "$concat" -c copy "$tmp/base.mp4" -y 2>/dev/null; then
      echo "⚠  stream-copy 拼接失败，回退到重新编码"
      ffmpeg -f concat -safe 0 -i "$concat" -c:v libx264 -preset fast -crf 23 \
        -c:a aac "$tmp/base.mp4" -y 2>/dev/null
    fi
    cp "$tmp/base.mp4" "$out"
  fi

  # ── 5. BGM ──
  # BGM 跟 logo/cover 不一样——它会实打实地改变听感，不能因为 resources/ 目录里
  # 刚好放了个 bgm.mp3 就默默给所有视频都混上（真出过事：resources/bgm.mp3 一直在，
  # resolve_asset 的 auto-detect 一修好，所有视频封面部分就多出一段没人要的底噪/音乐）。
  # 必须 meta 显式设成 true 或给具体路径才启用，None/未设置/false 都不启用。
  local bgm_flag=$(meta_get "$meta" "bgm")
  local bgm=""
  if [ "$bgm_flag" != "false" ] && [ "$bgm_flag" != "None" ] && [ "$bgm_flag" != "null" ] && [ -n "$bgm_flag" ]; then
    bgm=$(resolve_asset "$dir" "$meta" "bgm")
  fi
  if [ -n "$bgm" ] && [ -f "$bgm" ]; then
    echo "➜ 混入 BGM..."
    local bgm_vol=$(meta_get "$meta" "bgm_volume")
    ffmpeg -i "$out" -i "$bgm" -filter_complex "[1:a]volume=${bgm_vol:-0.15}[bgm];[0:a][bgm]amix=inputs=2:duration=first" \
      -c:v copy "$tmp/final.mp4" -y 2>/dev/null
    mv "$tmp/final.mp4" "$out"
  fi

  # ── 6. 封面缩略图 ──
  # Finder/播放器的默认缩略图往往是从视频中段抽的，不是第 0 帧，
  # 即使第 0 帧就是封面也不保证被当缩略图用。把第 0 帧作为 attached_pic
  # 内嵌进容器（跟 MP3 内嵌专辑封面同一种机制），播放器/Finder 默认显示的就是它，
  # 跟播放进度、有没有拖动过没关系。
  local poster="$tmp/poster.png"
  if ffmpeg -i "$out" -vframes 1 -f image2 "$poster" -y 2>/dev/null && [ -f "$poster" ]; then
    if ffmpeg -i "$out" -i "$poster" -map 0 -map 1 -c copy -c:v:1 png -disposition:v:1 attached_pic \
      "$tmp/with_poster.mp4" -y 2>/dev/null; then
      mv "$tmp/with_poster.mp4" "$out"
    fi
  fi

  rm -rf "$tmp"
}
