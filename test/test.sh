#!/bin/bash
# Video Toolkit 测试套件 v2
# 用法: cd test && bash test.sh
# 覆盖: meta引擎 / 幻灯片 / 合成器 / CLI入口 / 后端API

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$SCRIPT_DIR/.."
cd "$TOOLKIT_DIR"

PASS=0; FAIL=0; SKIP=0; TMP="/tmp/_vt_test_$$"
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[0;33m'; NC='\033[0m'

# ── Helpers ──
ok() { PASS=$((PASS+1)); echo -e "  ${GREEN}✅${NC} $1"; }
fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}❌${NC} $1"; }
skip() { SKIP=$((SKIP+1)); echo -e "  ${YELLOW}⚠${NC}  $1 (跳过)"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
assert() { [ "$1" = "$2" ] && ok "$3" || fail "$3 (期望 '$2', 实际 '$1')"; }
assert_file() { [ -f "$1" ] && ok "$2" || fail "$2 (缺失: $1)"; }
assert_size() { local sz=$(wc -c < "$1" 2>/dev/null || echo 0); [ "$sz" -gt "${2:-100}" ] && ok "$3 (${sz}B)" || fail "$3 (${sz}B)"; }
cleanup() { rm -rf "$TMP"; }

setup() {
  mkdir -p "$TMP"/{proj/feature-video,proj/feature-slide/slides,proj/feature-empty,proj/feature-both}
  ffmpeg -f lavfi -i "color=c=black:s=320x240:d=2:r=30" -f lavfi -i "anullsrc=r=44100:cl=mono" \
    -c:v libx264 -preset ultrafast -crf 28 -c:a aac -shortest \
    "$TMP/proj/feature-video/recording.mov" -y 2>/dev/null
  ffmpeg -f lavfi -i "color=c=gray:s=320x240:d=0.1:r=1" -frames:v 1 "$TMP/proj/feature-slide/slides/01.png" -y 2>/dev/null
  ffmpeg -f lavfi -i "color=c=navy:s=320x240:d=0.1:r=1" -frames:v 1 "$TMP/proj/feature-slide/slides/02.png" -y 2>/dev/null
  echo "第一页解说" > "$TMP/proj/feature-slide/slides/narration.txt"
  echo "第二页解说" >> "$TMP/proj/feature-slide/slides/narration.txt"
  ffmpeg -f lavfi -i "color=c=black:s=320x240:d=0.5:r=30" -f lavfi -i "anullsrc=r=44100:cl=mono" \
    -c:v libx264 -preset ultrafast -crf 28 -c:a aac -shortest \
    "$TMP/proj/feature-both/recording.mov" -y 2>/dev/null
  mkdir -p "$TMP/proj/feature-both/slides"
  [ -d .venv ] || python3 -m venv .venv 2>/dev/null || true
  echo "  测试环境: $TMP"
}

# ── Source libs ──
source lib/meta.sh 2>/dev/null || true
source lib/compose.sh 2>/dev/null || true
source lib/slides.sh 2>/dev/null || true

# ═══════ 测试 1: meta 引擎 ═══════
test_meta() {
  section "1. meta.json 引擎"

  # 1.1 默认值
  local meta=$(load_meta "$TMP/proj/feature-video")
  local type=$(meta_get "$meta" "type")
  assert "$type" "auto" "默认 type=auto"

  local voice=$(meta_get "$meta" "voice")
  assert "$voice" "zh-CN-XiaoxiaoNeural" "默认语音"

  # 1.2 类型检测
  local vtype=$(detect_type "$TMP/proj/feature-video" "$meta")
  assert "$vtype" "video" "feature+vide → video"

  local stype=$(detect_type "$TMP/proj/feature-slide" "$meta")
  assert "$stype" "slide" "feature+slide → slide"

  local etype=$(detect_type "$TMP/proj/feature-empty" "$meta")
  assert "$etype" "error: 未找到 recording.mov 或 slides/" "空目录 → error"

  # 1.3 资源查找
  local cover=$(resolve_asset "$TMP/proj/feature-video" "$meta" "cover")
  assert "$cover" "" "无cover返回空"

  # 1.4 深度合并
  local merged=$(merge_json '{"voice":"old"}' '{"voice":"new","type":"slide"}')
  local mv=$(python3 -c "import json;print(json.loads('''$merged''')['voice'])")
  assert "$mv" "new" "merge: feature覆盖project"
}

# ═══════ 测试 2: 幻灯片 ═══════
test_slides() {
  section "2. 幻灯片系统"
  local dir="$TMP/proj/feature-slide"
  local meta=$(load_meta "$dir")

  # 2.1 build_pages
  local pages=$(build_pages "$dir" "$meta")
  local count=$(python3 -c "import json;print(len(json.loads('''$pages''')))")
  assert "$count" "2" "build_pages: 2页"

  # 2.2 解说三级回退
  local txt=$(get_narration "$dir/slides" "01.png" 0)
  assert "$txt" "第一页解说" "get_narration: narration.txt行1"

  local txt2=$(get_narration "$dir/slides" "02.png" 1)
  assert "$txt2" "第二页解说" "get_narration: narration.txt行2"

  # 2.3 gen_slide_video（仅当 edge-tts 可用）
  if $EDGE --help > /dev/null 2>&1; then
    gen_slide_video "$pages" "$meta" "$dir" "$TMP/_test_slides.mp4"
    assert_file "$TMP/_test_slides.mp4" "gen_slide_video 成功"
    assert_size "$TMP/_test_slides.mp4" 500 "幻灯片视频大小正常"
    rm -f "$TMP/_test_slides.mp4"
  else
    skip "slide生成测试 (edge-tts未安装)"
  fi
}

# ═══════ 测试 3: 合成器 ═══════
test_compose() {
  section "3. compose_final"
  local meta=$(load_meta "$TMP/proj/feature-video")
  local content="$TMP/proj/feature-video/recording.mov"
  compose_final "$content" "$meta" "$TMP/proj/feature-video" "$TMP/_test_compose.mp4"
  assert_file "$TMP/_test_compose.mp4" "生成 final.mp4"
  assert_size "$TMP/_test_compose.mp4" 500 "文件大小正常"
  rm -f "$TMP/_test_compose.mp4"
}

# ═══════ 测试 4: 错误处理 ═══════
test_errors() {
  section "4. 错误处理"
  local meta=$(load_meta "$TMP/proj/feature-empty")
  local type=$(detect_type "$TMP/proj/feature-empty" "$meta")
  assert "$type" "error: 未找到 recording.mov 或 slides/" "空目录→error"

  local cover=$(resolve_asset "$TMP/proj/feature-empty" "$meta" "cover")
  assert "$cover" "" "resolve_asset→静默返回空"

  local meta2=$(load_meta "/nonexistent_$$")
  local type2=$(meta_get "$meta2" "type")
  assert "$type2" "auto" "无目录→回退默认"
}

# ═══════ 测试 5: Python 代码语法 ═══════
test_python_syntax() {
  section "5. Python 代码语法"
  python3 -c "import py_compile,os; d='$TOOLKIT_DIR'
for f in ['backend/server.py']:
  try: py_compile.compile(os.path.join(d,f),doraise=True); ok(f'  {f} 语法OK')
  except py_compile.PyCompileError as e: fail(f'  {f} 语法错误: {e}')" 2>/dev/null

  # 检查 shell 脚本语法
  bash -n "$TOOLKIT_DIR/video-toolkit.sh" 2>/dev/null && ok "video-toolkit.sh 语法OK" || fail "video-toolkit.sh 语法错误"
  bash -n "$TOOLKIT_DIR/lib/meta.sh" 2>/dev/null && ok "lib/meta.sh 语法OK" || fail "lib/meta.sh 语法错误"
  bash -n "$TOOLKIT_DIR/lib/slides.sh" 2>/dev/null && ok "lib/slides.sh 语法OK" || fail "lib/slides.sh 语法错误"
  bash -n "$TOOLKIT_DIR/lib/compose.sh" 2>/dev/null && ok "lib/compose.sh 语法OK" || fail "lib/compose.sh 语法错误"
}

# ═══════ 测试 6: CLI 入口 ═══════
test_cli() {
  section "6. CLI 入口"
  local script="$TOOLKIT_DIR/video-toolkit.sh"
  assert_file "$script" "video-toolkit.sh 存在"

  # 测试 --version
  bash "$script" --version 2>/dev/null > /dev/null && ok "--version OK" || fail "--version 失败"

  # 测试 --help
  local help=$(bash "$script" 2>&1 || true)
  echo "$help" | grep -q "录屏处理工具\|Usage\|vt " && ok "--help 有效" || fail "--help 无效"
}

# ═══════ Main ═══════
main() {
  echo "🧪 Video Toolkit 测试套件 v2"
  setup
  test_meta
  test_slides
  test_compose
  test_errors
  test_python_syntax
  test_cli
  cleanup
  echo ""
  echo "========================================"
  echo -e "  ${GREEN}$PASS 通过${NC} / ${RED}$FAIL 失败${NC} / ${YELLOW}$SKIP 跳过${NC}"
  echo "========================================"
  [ $FAIL -eq 0 ]
}

main "$@"
