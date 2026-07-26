#!/bin/bash
# Video Toolkit 测试套件 — 用法: cd test && bash test.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$SCRIPT_DIR/.."
cd "$TOOLKIT_DIR"

source lib/meta.sh
source lib/compose.sh
source lib/slides.sh

PASS=0; FAIL=0; TMP="/tmp/_vt_test_$$"
mkdir -p "$TMP"

G='\033[0;32m'; R='\033[0;31m'; C='\033[0;36m'; N='\033[0m'

ok()  { PASS=$((PASS+1)); echo -e "  ${G}✅${N} $1"; }
bad() { FAIL=$((PASS+1)); echo -e "  ${R}❌${N} $1"; }
sec() { echo -e "\n${C}━━━ $1 ━━━${N}"; }

# ── 夹具 ──
setup() {
  mkdir -p "$TMP/project/feature-video" "$TMP/project/feature-slide/slides" "$TMP/project/feature-empty"

  ffmpeg -f lavfi -i "color=c=black:s=320x240:d=2:r=30" -f lavfi -i "anullsrc=r=44100:cl=mono" \
    -c:v libx264 -preset ultrafast -crf 28 -c:a aac -shortest \
    "$TMP/project/feature-video/recording.mov" -y 2>/dev/null

  ffmpeg -f lavfi -i "color=c=gray:s=320x240:d=0.1:r=1" -frames:v 1 "$TMP/project/feature-slide/slides/01.png" -y 2>/dev/null
  ffmpeg -f lavfi -i "color=c=navy:s=320x240:d=0.1:r=1" -frames:v 1 "$TMP/project/feature-slide/slides/02.png" -y 2>/dev/null
  echo "第一页解说" > "$TMP/project/feature-slide/slides/narration.txt"
  echo "第二页解说" >> "$TMP/project/feature-slide/slides/narration.txt"

  [ -d .venv ] || python3 -m venv .venv 2>/dev/null || true
}

teardown() {
  rm -rf "$TMP"
  echo -e "\n${C}结果:${N} ${G}$PASS 通过${N} / ${R}$FAIL 失败${N}"
  [ $FAIL -eq 0 ]
}

# ── 1. meta 引擎 ──
test_meta() {
  sec "1. meta 引擎"
  local meta=$(load_meta "$TMP/project/feature-video")
  [ "$(meta_get "$meta" type)" = "auto" ] && ok "默认 type=auto" || bad "默认 type"
  [ "$(meta_get "$meta" voice)" = "zh-CN-XiaoxiaoNeural" ] && ok "默认语音" || bad "默认语音"
  
  local vt=$(detect_type "$TMP/project/feature-video" "$meta")
  [ "$vt" = "video" ] && ok "video 检测" || bad "video 检测: $vt"
  
  local st=$(detect_type "$TMP/project/feature-slide" "$meta")
  [ "$st" = "slide" ] && ok "slide 检测" || bad "slide 检测: $st"
  
  local et=$(detect_type "$TMP/project/feature-empty" "$meta")
  [[ "$et" == error:* ]] && ok "空目录→error" || bad "空目录: $et"
  
  local cov=$(resolve_asset "$TMP/project/feature-video" "$meta" "cover")
  [ "$cov" = "" ] && ok "无cover→空" || bad "cover: $cov"

  local m=$(merge_json '{"voice":"old"}' '{"voice":"new","type":"slide"}')
  [ "$(python3 -c "import json;print(json.loads('$m')['voice'])")" = "new" ] && ok "merge覆盖" || bad "merge"
  [ "$(python3 -c "import json;print(json.loads('$m')['type'])")" = "slide" ] && ok "merge新增" || bad "merge"
}

# ── 2. 合成器 ──
test_compose() {
  sec "2. compose_final"
  local meta=$(load_meta "$TMP/project/feature-video")
  compose_final "$TMP/project/feature-video/recording.mov" "$meta" "$TMP/project/feature-video" "$TMP/_c.mp4"
  [ -f "$TMP/_c.mp4" ] && ok "生成成功" || bad "生成失败"
  [ $(wc -c < "$TMP/_c.mp4") -gt 500 ] && ok "大小>500B" || bad "太小"
  rm -f "$TMP/_c.mp4"
}

# ── 3. 幻灯片 ──
test_slides() {
  sec "3. 幻灯片"
  local dir="$TMP/project/feature-slide"
  local meta=$(load_meta "$dir")
  local pages=$(build_pages "$dir" "$meta")
  local cnt=$(python3 -c "import json;print(len(json.loads('$pages')))" 2>/dev/null || echo 0)
  [ "$cnt" = "2" ] && ok "pages=2" || bad "pages=$cnt"
  
  local t1=$(get_narration "$dir/slides" "01.png" 0)
  [ "$t1" = "第一页解说" ] && ok "解说行1" || bad "解说: $t1"
  
  gen_slide_video "$pages" "$meta" "$dir" "$TMP/_s.mp4"
  [ -f "$TMP/_s.mp4" ] && ok "slide视频成功" || bad "slide失败"
  rm -f "$TMP/_s.mp4"
}

# ── 4. 错误处理 ──
test_errors() {
  sec "4. 错误处理"
  local meta=$(load_meta "$TMP/project/feature-empty")
  [[ $(detect_type "$TMP/project/feature-empty" "$meta") == error:* ]] && ok "空目录→error" || bad "空目录未报错"
  [ "$(resolve_asset "$TMP/project/feature-empty" "$meta" "bgm")" = "" ] && ok "无bgm静默" || bad "bgm异常"
}

# ── 运行 ──
setup
test_meta
test_compose
test_slides
test_errors
teardown
