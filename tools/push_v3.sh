#!/bin/bash
# Push the digest-consistent packages (patched3) onto the SD card and verify.
set -u
D=/home/placeless/dev/p20-root/firmware/patched3
SD=/storage/D4DD-4FB0/dload

echo "=== local files ==="
ls -l "$D"

echo
echo "=== push main package ==="
timeout 30 adb shell "rm -f $SD/update_sd.zip"
timeout 900 adb push "$D/update_sd.zip" "$SD/update_sd.zip" 2>&1 | tail -2

echo
echo "=== push customized-data package ==="
timeout 30 adb shell "rm -f $SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip"
timeout 900 adb push "$D/update_sd_ANE-L22J_hw_jp.zip" "$SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip" 2>&1 | tail -2

echo
echo "=== verify on device (md5 must match) ==="
timeout 120 adb shell "ls -l $SD/update_sd.zip $SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip; echo; md5sum $SD/update_sd.zip $SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip"
echo "--- host:"
md5sum "$D/update_sd.zip" "$D/update_sd_ANE-L22J_hw_jp.zip"
