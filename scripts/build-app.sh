#!/bin/bash
# 从源码构建 SwitchBar.app（只需要 Xcode 或 Command Line Tools，没有任何第三方依赖）
#
# 可选环境变量：
#   SIGN_IDENTITY  代码签名身份。默认：钥匙串里有名为 "SwitchBar Local" 的证书就用它，否则临时签名（-）
#   UNIVERSAL=1    同时编译 Apple 芯片和 Intel 版本（需要完整的 Xcode）
#   VERSION=1.2.3  写入应用的版本号（发布流程会用标签名自动设置）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="SwitchBar"
BUNDLE_ID="local.switchbar"
APP="$ROOT/dist/$APP_NAME.app"

ARCH_FLAGS=""
if [ "${UNIVERSAL:-0}" = "1" ]; then
  ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

if [ -z "${SIGN_IDENTITY:-}" ]; then
  if security find-identity -p codesigning 2>/dev/null | grep -q '"SwitchBar Local"'; then
    SIGN_IDENTITY="SwitchBar Local"
  else
    SIGN_IDENTITY="-"
  fi
fi

echo "==> 编译（release）"
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS
# shellcheck disable=SC2086
BIN_DIR="$(swift build -c release $ARCH_FLAGS --show-bin-path)"

echo "==> 生成图标"
ICNS="$ROOT/.build/AppIcon.icns"
# 图标脚本改过就重新生成
if [ ! -f "$ICNS" ] || [ "$ROOT/scripts/make-icon.swift" -nt "$ICNS" ]; then
  ICONSET="$ROOT/.build/AppIcon.iconset"
  rm -rf "$ICONSET"
  swift "$ROOT/scripts/make-icon.swift" "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$ICNS"
fi

echo "==> 打包 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$APP/Contents/Info.plist"
fi

echo "==> 签名（身份：${SIGN_IDENTITY}，强化运行时）"
# --options runtime：强化运行时，禁止其他程序注入代码或调试附加，防止借用 SwitchBar 的系统权限
codesign --force --options runtime --entitlements "$ROOT/Resources/SwitchBar.entitlements" \
  --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict --verbose=1 "$APP"

if [ "$SIGN_IDENTITY" = "-" ]; then
  echo
  echo "提示：当前是临时签名。每次重新编译后，「辅助功能」权限需要删掉重新添加。"
  echo "      按 README 创建一个名为 \"SwitchBar Local\" 的自签名证书即可避免。"
fi
echo
echo "完成：$APP"
