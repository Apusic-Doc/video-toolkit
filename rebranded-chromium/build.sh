#!/bin/bash
# 从 Playwright 缓存里的 Chromium 生成一份重新签名、改过 Bundle 身份的副本，
# 让录制时菜单栏/进程名显示"Apusic 功能验证"而不是"Google Chrome for Testing"。
#
# 何时需要重跑：`npx playwright install` 升级了 chromium 版本之后
# （版本号变了，playwright.config.js 里 executablePath 指向的路径不受影响，
#  因为这里固定输出到同一个目录/文件名，直接覆盖即可）。
set -euo pipefail

CACHE_DIR="$HOME/Library/Caches/ms-playwright"
SRC=$(find "$CACHE_DIR" -maxdepth 3 -iname "Google Chrome for Testing.app" -print -quit)
[ -z "$SRC" ] && { echo "未找到 Playwright 的 Chromium，先跑 npx playwright install"; exit 1; }

DEST_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$DEST_DIR/Apusic 功能验证.app"
NEW_NAME="Apusic 功能验证"

echo "源: $SRC"
echo "目标: $DEST"

rm -rf "$DEST"
ditto "$SRC" "$DEST"

# CFBundleExecutable 必须和 Contents/MacOS 下的真实二进制文件名一致，
# 否则系统认不出可执行文件在哪
mv "$DEST/Contents/MacOS/Google Chrome for Testing" "$DEST/Contents/MacOS/$NEW_NAME"
plutil -replace CFBundleExecutable -string "$NEW_NAME" "$DEST/Contents/Info.plist"
plutil -replace CFBundleName -string "$NEW_NAME" "$DEST/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$NEW_NAME" "$DEST/Contents/Info.plist"

# 改过 Info.plist 之后原有签名失效，必须重新签名（ad-hoc 签名足够本地运行，不需要开发者证书）
codesign --force --deep --sign - "$DEST"

echo "✅ 完成: $DEST"
echo "   验证: 直接跑该 app 的可执行文件（不要用 open -a，Launch Services 缓存可能仍指向旧身份）："
echo "   \"$DEST/Contents/MacOS/$NEW_NAME\" --start-maximized about:blank"
