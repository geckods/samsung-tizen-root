#!/bin/bash
set -u
TV=$1
CMD=$2
SDB=${SDB:-sdb}
if ! command -v "$SDB" >/dev/null 2>&1; then
  printf 'tvroot: sdb not found; set SDB or PATH\n' >&2
  exit 2
fi
B=TVROOTBEGIN$$
E=TVROOTEND$$
S=TVROOTDONE$$
RAW=$(mktemp)
trap 'rm -f "$RAW"' EXIT
timeout 15 "$SDB" connect "$TV" >/dev/null 2>&1 || true
timeout 20 "$SDB" -s "$TV" shell "0 hyperuart_vddebugmenu" > "$RAW" 2>&1 < <(
  printf '20089999\n94\n7\n1\nx;pkill -f dlogd_sdb;#\n1\nx;echo %s;%s;echo %s;echo %s;#\n' "$B" "$CMD" "$E" "$S"
  printf '99\n99\n99\n'
) &
SPID=$!
for _ in $(seq 1 200); do
  grep -q -a "^$S" "$RAW" 2>/dev/null && break
  kill -0 "$SPID" 2>/dev/null || break
  sleep 0.1
done
kill -9 "$SPID" 2>/dev/null
wait "$SPID" 2>/dev/null
tr -d '\r' < "$RAW" | awk -v b="$B" -v e="$E" '$0==b{p=1;next} $0==e{p=0} p'
