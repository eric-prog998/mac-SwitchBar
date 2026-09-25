#!/bin/bash
# 检查「编译出来的程序」本身（而不只是源码）：
#   1. 没有调用任何联网函数（socket、URLSession、Network.framework……）
#   2. 没有链接联网相关的框架
#   3. 以「强化运行时」签名，且只有预期的 entitlements
# 用法：./scripts/audit-binary.sh [dist/SwitchBar.app]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/SwitchBar.app}"
BIN="$APP/Contents/MacOS/SwitchBar"
status=0

if [ ! -f "$BIN" ]; then
  echo "找不到 $BIN，请先执行 make build"
  exit 1
fi

echo "== 1. 程序调用的联网函数（应为空） =="
# nm -u 列出程序需要从系统里调用的全部函数 / 类
SYMBOLS="$(for arch in $(lipo -archs "$BIN"); do nm -u -arch "$arch" "$BIN"; done | sort -u)"
C_NETWORK='^_(socket|connect|bind|listen|accept|sendto|recvfrom|getaddrinfo|gethostbyname|gethostbyname2)$'
API_NETWORK='URLSession|NSURLConnection|NSURLRequest|URLRequest|NSURLDownload|_nw_|CFSocket|CFStream|CFHTTP|CFNetService|SCNetworkReachability|WKWebView|NSNetService|NWConnection|NWListener|NWPathMonitor'
FOUND="$(echo "$SYMBOLS" | grep -E "$C_NETWORK|$API_NETWORK")"
if [ -n "$FOUND" ]; then
  echo "$FOUND"
  echo "!! 程序里出现了联网函数"
  status=1
else
  echo "未发现（共检查 $(echo "$SYMBOLS" | wc -l | tr -d ' ') 个外部符号）"
fi

echo
echo "== 2. 链接的系统框架 =="
LIBS="$(otool -L "$BIN" | tail -n +2 | awk '{print $1}' | sort -u)"
echo "$LIBS"
if echo "$LIBS" | grep -Eq 'Network\.framework|CFNetwork\.framework|WebKit\.framework'; then
  echo "!! 链接了联网相关的框架"
  status=1
fi

echo
echo "== 3. 代码签名 =="
SIGN_INFO="$(codesign -dv "$APP" 2>&1)"
echo "$SIGN_INFO" | grep -E '^(Identifier|CodeDirectory|Signature|Authority)' || true
if echo "$SIGN_INFO" | grep -q 'flags=.*runtime'; then
  echo "强化运行时：已开启"
else
  echo "!! 没有开启强化运行时"
  status=1
fi

echo
echo "== 4. Entitlements（应只有 com.apple.security.automation.apple-events） =="
ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null | grep -o '<key>[^<]*</key>' | sed 's/<[^>]*>//g')"
echo "${ENTITLEMENTS:-（无）}"
UNEXPECTED="$(echo "$ENTITLEMENTS" | grep -v '^com.apple.security.automation.apple-events$' | grep -v '^$')"
if [ -n "$UNEXPECTED" ]; then
  echo "!! 出现了预期之外的 entitlements"
  status=1
fi

exit $status
