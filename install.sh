#!/bin/bash
# ============================================================
# Video Toolkit — 一键安装脚本
# 用法: curl -sSf https://video-toolkit.bitey.ai/install.sh | bash
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

INSTALL_DIR="${VIDEO_TOOLKIT_HOME:-$HOME/.video-toolkit}"
REPO_URL="https://github.com/Apusic-Doc/video-toolkit.git"

echo ""
echo -e "${CYAN}${BOLD}🎬 Video Toolkit Installer${NC}"
echo "========================================"
echo ""

# ── 环境检查 ──
check_cmd() {
  command -v "$1" &>/dev/null && echo -e "  ${GREEN}✅${NC} $1" || { echo -e "  ${RED}❌${NC} $1 (请先安装)"; exit 1; }
}
check_cmd bash
check_cmd curl
check_cmd git
check_cmd python3
check_cmd ffmpeg

# ── 下载 ──
if [ -d "$INSTALL_DIR" ]; then
  echo ""
  echo -e "  ${CYAN}➜${NC} 更新现有安装..."
  cd "$INSTALL_DIR"
  git pull --rebase 2>/dev/null || true
else
  echo ""
  echo -e "  ${CYAN}➜${NC} 下载到 $INSTALL_DIR..."
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

# ── 安装依赖 ──
echo ""
echo -e "  ${CYAN}➜${NC} 配置 Python 虚拟环境..."
cd "$INSTALL_DIR"
echo -ne "  ⏳ 安装中..."

python3 -m venv .venv 2>/dev/null || true

# 后台安装 + 旋转等待
(
.venv/bin/pip install -q edge-tts faster-whisper 2>/dev/null
) &
pid=$!
spin='⣾⣽⣻⢿⡿⣟⣯⣷'
i=0
while kill -0 "$pid" 2>/dev/null; do
  c=${spin:$((i % 8)):1}
  echo -ne "\r  ${c} 安装依赖中..."
  sleep 0.5
  ((i++))
done
wait $pid
echo -e "\r  ${GREEN}✅${NC} 依赖安装完成"

# ── 创建全局命令 ──
mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/video-toolkit" << 'WRAPPER'
#!/bin/bash
INSTALL_DIR="${VIDEO_TOOLKIT_HOME:-$HOME/.video-toolkit}"
export VIDEO_FEATURES_DIR="${VIDEO_FEATURES_DIR:-$PWD}"

case "${1:-}" in
  --version|-v|version)
    cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "unknown"
    exit 0 ;;
  --update|update|upgrade)
    echo "🔄 更新 Video Toolkit..."
    cd "$INSTALL_DIR"
    rm -f VERSION
    git pull 2>&1 | tail -1
    echo "✅ 更新完成 ($(cat VERSION 2>/dev/null || echo '?'))"
    exit 0 ;;
esac

cd "$INSTALL_DIR"
source .venv/bin/activate 2>/dev/null
exec bash "$INSTALL_DIR/video-toolkit.sh" "$@"
WRAPPER
chmod +x "$HOME/.local/bin/video-toolkit"

# ── vt 别名 ──
ln -sf "$HOME/.local/bin/video-toolkit" "$HOME/.local/bin/vt"

# ── PATH 检测 ──
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  SHELL_RC="$HOME/.zshrc"
  [ -f "$HOME/.bashrc" ] && SHELL_RC="$HOME/.bashrc"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
  echo ""
  echo -e "  ${CYAN}➜${NC} 已将 ~/.local/bin 加入 PATH ($SHELL_RC)"
  echo "     source $SHELL_RC  或重开终端生效"
fi

# ── 完成 ──
echo ""
echo "========================================"
echo -e "  ${GREEN}${BOLD}✅ 安装完成！${NC}"
echo ""
echo "  全局命令:   video-toolkit"
echo "  安装目录:   $INSTALL_DIR"
echo ""
echo "  快速开始:"
echo "    video-toolkit status --help"
echo "    video-toolkit all <feature-dir>"
echo ""
echo "  ASR 引擎 (默认 faster-whisper):"
echo "    pip3 install funasr-onnx modelscope  # 可选：SenseVoice"
echo "    export VIDEO_ASR=funasr"
echo ""
echo "  更新: curl -sSf https://video-toolkit.bitey.ai/install.sh | bash"
echo "  卸载: rm -rf $INSTALL_DIR ~/.local/bin/video-toolkit ~/.local/bin/vt"
echo "========================================"
