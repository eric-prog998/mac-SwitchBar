#!/bin/bash
# 启动与资源占用测试：启动 SwitchBar，等它空闲下来，测量常驻时的内存、CPU 和唤醒次数。
# 超过下面的上限就返回失败（CI 会变红），防止以后的改动让 SwitchBar 变「重」。
# 用法：./scripts/resource-test.sh [dist/SwitchBar.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/SwitchBar.app}"
IDLE_SECONDS="${IDLE_SECONDS:-60}"
# 常驻内存上限（MB，系统「活动监视器」里显示的「内存」就是这个值）。
# 2.0 在 CI 上实测约 8–10 MB（1.3 是 20–27 MB），留一些余量
MAX_FOOTPRINT_MB="${MAX_FOOTPRINT_MB:-20}"
# 空闲期间允许用掉的 CPU 时间（秒）。2.0 实测 60 秒不到 0.02 秒（1.3 约 0.8–1 秒）
MAX_IDLE_CPU_S="${MAX_IDLE_CPU_S:-0.1}"

TMP="$(mktemp -d)"
MEASURE="$TMP/measure"
swiftc -O "$ROOT/scripts/measure.swift" -o "$MEASURE"

value() { echo "$1" | sed -E "s/.*$2=([0-9.]+).*/\1/"; }

pkill -x SwitchBar 2>/dev/null || true
open "$APP"
PID=""
for _ in $(seq 1 40); do
  PID="$(pgrep -x SwitchBar || true)"
  [ -n "$PID" ] && break
  sleep 0.25
done
if [ -z "$PID" ]; then
  echo "!! SwitchBar 没有启动"
  exit 1
fi

sleep 5
START="$("$MEASURE" "$PID")"
echo "启动 5 秒后：$START"
sleep "$IDLE_SECONDS"
if ! kill -0 "$PID" 2>/dev/null; then
  echo "!! SwitchBar 在空闲时退出了（可能崩溃）"
  exit 1
fi
END="$("$MEASURE" "$PID")"
echo "再空闲 ${IDLE_SECONDS} 秒后：$END"
pkill -x SwitchBar || true

FOOTPRINT="$(value "$END" footprint_mb)"
IDLE_CPU="$(awk "BEGIN { printf \"%.3f\", $(value "$END" cpu_s) - $(value "$START" cpu_s) }")"
WAKEUPS="$(( $(value "$END" idle_wakeups) - $(value "$START" idle_wakeups) ))"
SIZE_KB="$(du -sk "$APP" | awk '{print $1}')"

echo
echo "== 结果 =="
echo "安装包大小：$(( SIZE_KB / 1024 )) MB（${SIZE_KB} KB）"
echo "常驻内存：${FOOTPRINT} MB（上限 ${MAX_FOOTPRINT_MB} MB）"
echo "空闲 ${IDLE_SECONDS} 秒用掉的 CPU 时间：${IDLE_CPU} 秒（上限 ${MAX_IDLE_CPU_S} 秒）"
echo "空闲 ${IDLE_SECONDS} 秒内的唤醒次数：${WAKEUPS}"

status=0
if awk "BEGIN { exit !($FOOTPRINT > $MAX_FOOTPRINT_MB) }"; then
  echo "!! 常驻内存超过上限"
  status=1
fi
if awk "BEGIN { exit !($IDLE_CPU > $MAX_IDLE_CPU_S) }"; then
  echo "!! 空闲时 CPU 占用超过上限"
  status=1
fi
exit $status
