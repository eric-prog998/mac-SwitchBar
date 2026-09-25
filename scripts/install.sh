#!/bin/bash
# 构建并安装到 /Applications，然后启动
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh"

TARGET="/Applications/SwitchBar.app"
echo "==> 安装到 $TARGET"
pkill -x SwitchBar 2>/dev/null || true
sleep 0.5
rm -rf "$TARGET"
cp -R "$ROOT/dist/SwitchBar.app" "$TARGET"
open "$TARGET"
echo "已启动，菜单栏右上角会出现 SwitchBar 的开关图标。"
