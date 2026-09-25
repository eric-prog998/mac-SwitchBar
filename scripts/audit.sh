#!/bin/bash
# 安全自查：列出 SwitchBar 源码里所有「值得关心」的东西。
#   1. 网络访问（应该一个都没有，有的话脚本返回失败，CI 会变红）
#   2. 会执行的外部命令
#   3. 用到的非公开系统框架
#   4. 第三方依赖（应该没有）
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
status=0

echo "== 1. 网络相关代码（应为空） =="
NETWORK_PATTERN='URLSession|NSURLConnection|NSURLRequest|URLRequest|NWConnection|NWListener|NWPathMonitor|Network\.framework|import Network|CFSocket|CFStream|CFNetwork|socket\(|getaddrinfo|WKWebView|WebView|https?://'
if grep -rnE "$NETWORK_PATTERN" Sources; then
  echo "!! 发现可能的网络访问，请检查上面列出的代码"
  status=1
else
  echo "未发现"
fi

echo
echo "== 2. 会执行的外部命令 =="
grep -rhoE '"/(usr/)?s?bin/[A-Za-z0-9_-]+"' Sources | sort -u

echo
echo "== 3. 非公开系统框架 =="
grep -rhoE '/System/Library/PrivateFrameworks/[A-Za-z]+\.framework' Sources | sort -u

echo
echo "== 4. 第三方依赖（应为空） =="
if grep -nE '\.package\(' Package.swift; then
  echo "!! 发现第三方依赖"
  status=1
else
  echo "未发现"
fi

exit $status
