#!/usr/bin/env bash
#
# 把构建好的 Clip.app 打成一个可分发的 DMG（内含 /Applications 软链接）。
#
# 用法：
#   Scripts/make-dmg.sh <Clip.app 路径> <输出目录> <版本号>
#
# 例：
#   Scripts/make-dmg.sh build/Build/Products/Release/Clip.app dist v1.0.0
#
# 只用系统自带的 hdiutil，不依赖第三方工具，本地和 CI 行为一致。
set -euo pipefail

APP_PATH="${1:?用法: make-dmg.sh <Clip.app 路径> <输出目录> <版本号>}"
OUT_DIR="${2:?缺少输出目录}"
VERSION="${3:?缺少版本号}"

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
[ -d "$APP_PATH" ] || { echo "找不到 app：$APP_PATH" >&2; exit 1; }

APP_NAME="$(basename "$APP_PATH" .app)"
# 版本号里的 v 前缀不放进文件名，避免出现 Clip-v1.0.0.dmg 这种双份前缀
SAFE_VERSION="${VERSION#v}"
DMG_NAME="${APP_NAME}-${SAFE_VERSION}.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# DMG 里是「拖进 Applications」的经典布局
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
rm -f "$OUT_DIR/$DMG_NAME"

# UDZO = 压缩只读镜像，体积最小。
# macOS 27 起 hdiutil create 已废弃（会打 deprecation 警告），改用 diskutil image create from；
# 旧系统上退回到 hdiutil，保证脚本在哪都能跑。
if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from \
    --format UDZO \
    --volumeName "$APP_NAME" \
    "$STAGE" \
    "$OUT_DIR/$DMG_NAME" >/dev/null
else
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$OUT_DIR/$DMG_NAME" >/dev/null
fi

echo "已生成：$OUT_DIR/$DMG_NAME"
