#!/bin/bash
# Push the patched package straight onto the phone's SD card over adb -
# no need to pull the card out of the device.
set -u
NEW=/home/placeless/dev/p20-root/firmware/patched/update_sd.zip
CON=/home/placeless/dev/p20-root/firmware/patched/update_sd_ANE-L22J_hw_jp.zip
ORIG=/tmp/fw3/Software/dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip

echo "=== locate the external SD volume on the device ==="
timeout 30 adb shell 'ls -1 /storage/ 2>&1'
echo
echo "=== volumes and free space ==="
timeout 30 adb shell 'df -h /storage/* 2>/dev/null | head -10; echo; echo "--- mount table:"; mount | grep -iE "fuse|vfat|/storage" | head -10'
echo
echo "=== existing dload dir? ==="
timeout 30 adb shell 'ls -l /storage/*/dload 2>&1 | head -10'
