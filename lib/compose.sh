#!/bin/bash
# ============================================================
# compose_final — 通用视频合成器
# ============================================================
# 用法: source lib/compose.sh
#       compose_final <content_video> <meta_json> <output>
# 功能: 封面 + 内容 + 封底 + BGM + 水印 = final.mp4
# ============================================================

# ── 生成封面片段（图片或视频） ──
gen_cover() {
  local asset="$1" dur="$2" out="$3"
  if [[ "$asset" == *.mp4 || "$asset" == *.mov ]]; then
    # 视频封面：直接复制
    ffmpeg -i "$asset" -c:v libx264 -preset ultrafast -crf 23 -an "$out" -y 2>/dev/null && echo "$out"
  else
    # 图片封面：静态帧 + 时长
    ffmpeg -loop 1 -i "$asset" -c:v libx264 -preset ultrafast -crf 23 -t "$dur" -pix_fmt yuv420p -an "$out" -y 2>/dev/null && echo "$out"
  fi
}

# ── 生成封底片段 ──
gen_outro() {
  gen_cover "$1" "$2" "$3"  # 逻辑相同
}

# ── 主函数 ──
# compose_final <content_video> <meta_json> <feature_dir> <output.mp4>
compose_final() {
  local content="$1"; local meta="$2"; local dir="$3"; local out="$4"
  local project_dir="$(cd "$dir/.." && pwd)"
  local tmp="/tmp/_vt_final_$$"
  mkdir -p "$tmp"

  local parts=()
  local audio_src="$content"

  # ── 1. 封面 ──
  local cover=$(resolve_asset "$dir" "$meta" "cover")
  if [ -n "$cover" ]; then
    echo "➜ 添加封面..."
    local cover_dur=$(meta_get "$meta" "cover_duration")
    local cover_clip="$tmp/cover.mp4"
    if gen_cover "$cover" "${cover_dur:-3}" "$cover_clip"; then
      parts+=("$cover_clip")
    else
      echo "⚠  封面生成失败"
    fi
  fi

  # ── 2. 内容 ──
  parts+=("$content")

  # ── 3. 封底 ──
  local outro=$(resolve_asset "$dir" "$meta" "outro")
  if [ -n "$outro" ]; then
    echo "➜ 添加封底..."
    local outro_dur=$(meta_get "$meta" "outro_duration")
    local outro_clip="$tmp/outro.mp4"
    if gen_outro "$outro" "${outro_dur:-3}" "$outro_clip"; then
      parts+=("$outro_clip")
    else
      echo "⚠  封底生成失败"
    fi
  fi

  # ── 4. 拼接视频 ──
  if [ ${#parts[@]} -eq 1 ]; then
    cp "$content" "$tmp/base.mp4"
  else
    echo -ne "  ⏳ 拼接视频片段... "
    local concat="$tmp/concat.txt"
    > "$concat"
    for p in "${parts[@]}"; do echo "file '$p'" >> "$concat"; done
    ffmpeg -f concat -safe 0 -i "$concat" -c:v h264_videotoolbox -b:v 5M -r 30 \
      -c:a aac "$tmp/base.mp4" -y 2>/dev/null
    echo "✅"
  fi

  # ── 5. BGM ──
  local bgm=$(resolve_asset "$dir" "$meta" "bgm")
  if [ -n "$bgm" ] && [ -f "$bgm" ]; then
    echo "➜ 处理 BGM..."
    local bgm_vol=$(meta_get "$meta" "bgm_volume")
    local bgm_loop=$(meta_get "$meta" "bgm_loop")

    # 获取视频时长
    local vid_dur=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$tmp/base.mp4")

    # 生成匹配时长的 BGM
    local bgm_fit="$tmp/bgm_fit.wav"
    if [ "$bgm_loop" = "True" ]; then
      # 循环到匹配视频时长
      ffmpeg -stream_loop -1 -i "$bgm" -t "$vid_dur" -af "volume=${bgm_vol:-0.15}" "$bgm_fit" -y 2>/dev/null
    else
      # 不循环：截断或直接使用
      ffmpeg -i "$bgm" -t "$vid_dur" -af "volume=${bgm_vol:-0.15}" "$bgm_fit" -y 2>/dev/null
    fi

    # BGM 叠加到视频
    ffmpeg -i "$tmp/base.mp4" -i "$bgm_fit" -filter_complex "[1:a]adelay=0|0[bgm];[0:a][bgm]amix=inputs=2:duration=first" \
      -c:v copy -c:a aac "$tmp/mixed.mp4" -y 2>/dev/null
    [ -f "$tmp/mixed.mp4" ] && mv "$tmp/mixed.mp4" "$tmp/base.mp4"
  fi

  # ── 6. 输出 ──
  cp "$tmp/base.mp4" "$out"
  rm -rf "$tmp"
}
