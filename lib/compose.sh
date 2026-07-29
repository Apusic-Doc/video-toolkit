#!/bin/bash
# ============================================================
# compose_final — 通用视频合成器
# ============================================================

# ── 生成标题封面（白屏 + 居中文字）──
gen_title_card() {
  local title="$1" subtitle="$2" duration="${3:-3}" out="$4"
  local logo="$5" company="$6"
  [ -z "$title" ] && return 1
  local png="/tmp/_vt_cover_$$.png"
  local font=""
  for f in "/System/Library/Fonts/Supplemental/Songti.ttc"            "/System/Library/Fonts/STHeiti Medium.ttc"            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"            "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"; do
    [ -f "$f" ] && { font="$f"; break; }
  done
  # 1. 白色背景 + 居中标题/副标题
  magick -size 1920x1080 xc:white     -gravity center     ${font:+-font "$font"}     -fill '#222222' -pointsize 60 -draw "text 0,-60 '$title'"     -fill '#666666' -pointsize 42 -draw "text 0,30 '$subtitle'"     "$png" 2>/dev/null || return 1
  # 2. Logo 左上角（缩放到 60px 高，保留原色）
  if [ -n "$logo" ] && [ -f "$logo" ]; then
    local logo_small="/tmp/_vt_logo_$$.png"
    magick "$logo" -resize x60 "$logo_small" 2>/dev/null
    magick "$png" "$logo_small" -geometry +40+30 -composite "$png" 2>/dev/null
    rm -f "$logo_small"
  fi
  # 3. 公司名称 中下方
  if [ -n "$company" ]; then
    local bottom=$((1080 - 80))
    magick "$png" ${font:+-font "$font"} -fill '#999999' -pointsize 24       -gravity south -draw "text 0,50 '$company'" "$png" 2>/dev/null
  fi
  ffmpeg -loop 1 -i "$png" -f lavfi -i "anullsrc=r=48000:cl=mono"     -c:v libx264 -preset fast -crf 23 -t "$duration" -pix_fmt yuv420p -c:a aac -shortest "$out" -y 2>/dev/null
  rm -f "$png"
}

# ── 生成封面片段（图片或视频） ──
gen_cover() {
  local asset="$1" dur="$2" out="$3"
  if [[ "$asset" == *.mp4 || "$asset" == *.mov ]]; then
    ffmpeg -i "$asset" -c:v libx264 -preset ultrafast -crf 23 -an "$out" -y 2>/dev/null && echo "$out"
  else
    ffmpeg -loop 1 -i "$asset" -c:v libx264 -preset ultrafast -crf 23 -t "$dur" -pix_fmt yuv420p -an "$out" -y 2>/dev/null && echo "$out"
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
  local audio_src="$content"

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
    gen_title_card "$title" "${subtitle:-}" "${cover_dur:-3}" "$cover_clip" "$logo" "$company" 2>/dev/null
    if [ -f "$cover_clip" ]; then
      parts+=("$cover_clip")
    else
      echo "⚠  封面生成失败"
    fi
  elif [ -n "$cover" ] && [ "$cover" != "false" ]; then
    echo "➜ 添加封面..."
    local cover_clip="$tmp/cover.mp4"
    if gen_cover "$cover" "${cover_dur:-3}" "$cover_clip"; then
      parts+=("$cover_clip")
    else
      echo "⚠  封面生成失败"
    fi
  fi

  # ── 2. 正文内容 ──
  parts+=("$content")

  # ── 3. 封底 ──
  local outro=$(resolve_asset "$dir" "$meta" "outro")
  if [ -n "$outro" ] && [ "$outro" != "false" ]; then
    echo "➜ 添加封底..."
    local outro_dur=$(meta_get "$meta" "outro_duration")
    local outro_clip="$tmp/outro.mp4"
    if gen_outro "$outro" "${outro_dur:-3}" "$outro_clip"; then
      parts+=("$outro_clip")
    fi
  fi

  # ── 4. 拼接 ──
  if [ ${#parts[@]} -eq 1 ]; then
    cp "$content" "$out"
  else
    echo "⏳ 合成 ${#parts[@]} 个片段..."
    local concat="$tmp/concat.txt"
    > "$concat"
    for p in "${parts[@]}"; do echo "file '$p'" >> "$concat"; done
    ffmpeg -f concat -safe 0 -i "$concat" -c:v libx264 -preset fast -crf 23 \
      -c:a aac "$tmp/base.mp4" -y 2>/dev/null
    cp "$tmp/base.mp4" "$out"
  fi

  # ── 5. BGM ──
  local bgm=$(resolve_asset "$dir" "$meta" "bgm")
  if [ -n "$bgm" ] && [ -f "$bgm" ]; then
    echo "➜ 混入 BGM..."
    local bgm_vol=$(meta_get "$meta" "bgm_volume")
    ffmpeg -i "$out" -i "$bgm" -filter_complex "[1:a]volume=${bgm_vol:-0.15}[bgm];[0:a][bgm]amix=inputs=2:duration=first" \
      -c:v copy "$tmp/final.mp4" -y 2>/dev/null
    mv "$tmp/final.mp4" "$out"
  fi

  rm -rf "$tmp"
  echo "✅ $(basename "$out")"
}
