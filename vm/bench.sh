#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SECS=${BENCH_SECS:-10}
name=${1:-}
dir=$ROOT/vm/runs/$name

[ -n "$name" ] || { echo "usage: xmake vm bench <name>" >&2; exit 2; }
[ -f "$dir/qemu.pid" ] || { echo "no pid for $name" >&2; exit 2; }
pid=$(cat "$dir/qemu.pid")

sample() {
	awk '{print $14 + $15}' "/proc/$pid/stat" 2>/dev/null || echo 0
}

start=$(sample)
sleep "$SECS"
end=$(sample)
rss=$(awk '/VmRSS/ {print $2}' "/proc/$pid/status" 2>/dev/null || echo 0)
cpu=$(awk -v a="$start" -v b="$end" -v s="$SECS" 'BEGIN { printf "%.1f", (b - a) / 100 / s * 100 }')

echo "host qemu    ${cpu}% cpu over ${SECS}s, $((rss / 1024))MB rss"

if "$ROOT/scripts/yudae" vm exec "$name" "cat /proc/loadavg; free -m | awk '/Mem:/ {print \"guest mem \" \$3 \"/\" \$2 \"MB\"}'" 2>/dev/null; then
	:
else
	echo "guest exec unavailable"
fi
