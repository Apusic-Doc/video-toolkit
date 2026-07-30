#!/bin/bash
# ============================================================
# Video Toolkit 一键安装
# curl -sSf https://video-toolkit.bitey.ai/install.sh | bash
# ============================================================
set -e

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[0;33m'; NC='\033[0m'
ok() { echo -e "  ${GREEN}✅${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
info() { echo -e "  ${CYAN}➜${NC} $1"; }

INSTALL_DIR="$HOME/.local/share/video-toolkit"
INSTALL_BIN="$HOME/.local/bin/vt"

echo ""
info "Video Toolkit — 一键安装"
echo ""

# ── 依赖检测 ──
missing=""
command -v python3 &>/dev/null || missing="python3 $missing"
command -v ffmpeg &>/dev/null || missing="ffmpeg $missing"
command -v git &>/dev/null || missing="git $missing"

if [ -n "$missing" ]; then
    echo "  缺少依赖: $missing"
    echo "  macOS:   brew install $missing"
    echo "  Ubuntu:  sudo apt install $missing"
    exit 1
fi
ok "依赖就绪 (python3 + ffmpeg + git)"

# ── 下载 ──
info "下载 Video Toolkit..."
if [ -d "$INSTALL_DIR" ]; then
    cd "$INSTALL_DIR" && git pull --ff-only origin main 2>/dev/null && ok "已更新" || warn "git pull 失败，使用本地版本"
else
    git clone --depth 1 https://github.com/Apusic-Doc/video-toolkit.git "$INSTALL_DIR" 2>/dev/null || \
        die "下载失败，请检查网络: https://github.com/Apusic-Doc/video-toolkit"
    ok "下载完成"
fi

# ── Python venv ──
info "配置 Python 虚拟环境..."
cd "$INSTALL_DIR"
if [ ! -d ".venv" ]; then
    python3 -m venv .venv 2>/dev/null || python3 -m venv --without-pip .venv 2>/dev/null || true
fi

if [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
    ok "venv 就绪"
else
    warn "venv 创建失败，将使用系统 Python"
fi

# ── 安装 Python 依赖 ──
info "安装 Python 依赖..."
PIP="$INSTALL_DIR/.venv/bin/pip"
if [ -f "$PIP" ]; then
    "$PIP" install --quiet edge-tts faster-whisper 2>/dev/null && ok "edge-tts + faster-whisper" || \
    "$PIP" install --quiet --break-system-packages edge-tts faster-whisper 2>/dev/null || \
        warn "依赖安装失败，请手动: $PIP install edge-tts faster-whisper"
else
    pip3 install --quiet edge-tts faster-whisper 2>/dev/null && ok "edge-tts + faster-whisper (system pip)" || \
        warn "pip3 不可用，跳过 Python 依赖"
fi

# ── 安装命令 ──
info "安装 vt 命令..."
mkdir -p "$(dirname "$INSTALL_BIN")"

cat > "$INSTALL_BIN" << CMDEOF
#!/bin/bash
export VT_HOME="$INSTALL_DIR"
export VIDEO_PROJECTS_DIR="\${VIDEO_PROJECTS_DIR:-\$HOME/Apusic/Product/ApusicAS/Videos/projects}"

vt_main() {
    local cmd="\$1"; shift
    if [ "\$cmd" = "upgrade" ]; then
        cd "\$VT_HOME" && git pull origin main 2>/dev/null && \\
            echo "✅ 已更新" || echo "⚠️  更新失败，请手动: cd \$VT_HOME && git pull"
    else
        [ -f "\$VT_HOME/.venv/bin/activate" ] && source "\$VT_HOME/.venv/bin/activate" 2>/dev/null
        "\$VT_HOME/video-toolkit.sh" "\$cmd" "\$@"
    fi
}
vt_main "\$@"
CMDEOF

chmod +x "$INSTALL_BIN"
ok "vt 命令已安装 ($INSTALL_BIN)"

# ── PATH ──
if ! echo "$PATH" | grep -q "$(dirname "$INSTALL_BIN")"; then
    SHELL_RC=""
    [ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"
    [ -f "$HOME/.bashrc" ] && SHELL_RC="$HOME/.bashrc"
    
    if [ -n "$SHELL_RC" ]; then
        if ! grep -q "$(dirname "$INSTALL_BIN")" "$SHELL_RC" 2>/dev/null; then
            echo "export PATH=\"$(dirname "$INSTALL_BIN"):\$PATH\"" >> "$SHELL_RC"
            ok "已添加到 $SHELL_RC"
        fi
    else
        warn "请手动添加: export PATH=\"$(dirname "$INSTALL_BIN"):\$PATH\""
    fi
fi

# ── 配置目录 ──
mkdir -p "$HOME/.config/video-toolkit"
mkdir -p "$VIDEO_PROJECTS_DIR" 2>/dev/null || mkdir -p "$HOME/video-projects"

echo ""
ok "安装完成！"
echo ""
echo "  重启终端或执行:  source $SHELL_RC"
echo "  然后:             vt --version"
echo "  启动 UI:           vt ui"
echo ""
