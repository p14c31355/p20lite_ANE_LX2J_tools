#!/bin/bash
# For each downloaded firmware package: extract the KERNEL block, print its
# version string and the two symbols, so we can see which one is the build the
# device is actually running.
#
# The device's kernel reports:
#   Linux version 4.4.23+ (android@localhost) (gcc version 4.9.x 20150123
#   (prerelease) (GCC) ) #1 SMP PREEMPT Fri Mar 1 00:11:18 CST 2019
# The date+time is unique per build, so an exact match means the same kernel.
set -u
HERE=/home/placeless/dev/p20-root
W=${W:-/tmp/cand}
mkdir -p "$W"

for PKG in "$@"; do
  NAME=$(basename "$PKG")
  OUT="$W/${NAME%.*}"
  echo "=================================================================="
  echo "== $NAME"
  echo "=================================================================="
  bash "$HERE/fw_to_constants.sh" "$PKG" "$OUT" > "$OUT.log" 2>&1
  # the scan may have recursed into an inner zip, so look for the artefacts anywhere
  KIMG=$(find "$OUT" -name kernel.img -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2)
  KELF=$(find "$OUT" -name kernel.elf -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2)
  if [ -z "$KIMG" ]; then
    echo "  no KERNEL block - last lines of the log:"; tail -5 "$OUT.log"; continue
  fi
  echo "  kernel image: $(stat -c%s "$KIMG") bytes"
  echo "  --- kernel version string (from the reconstructed ELF):"
  strings -n 10 "${KELF:-$KIMG}" | grep -m2 -E "Linux version 4" | sed 's/^/    /'
  echo "  --- the two symbols and the number that actually matters:"
  F=$(nm -n "$KELF" 2>/dev/null | awk '$3=="fair_sched_class"{print $1; exit}')
  A=$(nm -n "$KELF" 2>/dev/null | awk '$3=="avc_cache"{print $1; exit}')
  if [ -n "$F" ] && [ -n "$A" ]; then
    echo "      fair_sched_class = 0x$F"
    echo "      avc_cache        = 0x$A"
    python3 - "$F" "$A" <<'PY'
import sys
f, a = (int(x, 16) for x in sys.argv[1:3])
d = a - f
print(f"      avc_cache - fair_sched_class = 0x{d:x}   ({d})")
PY
  else
    echo "      (symbols not found in the ELF)"
    grep -E "fair_sched_class|avc_cache" "$OUT.log" | sed 's/^/      /'
  fi
  echo
done

echo "=================================================================="
echo "== target: the device reports"
echo "==   Fri Mar 1 00:11:18 CST 2019"
echo "=================================================================="
