#!/bin/bash
# Push the EOCD-confusion packages and verify they landed intact.
set -u
D=/home/placeless/dev/p20-root/firmware/eocd
SD=/storage/D4DD-4FB0/dload

echo "=== local files ==="
ls -l "$D"

echo
echo "=== push main ==="
timeout 30 adb shell "rm -f $SD/update_sd.zip"
timeout 900 adb push "$D/update_sd.zip" "$SD/update_sd.zip" 2>&1 | tail -2

echo
echo "=== push customized-data ==="
timeout 30 adb shell "rm -f $SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip"
timeout 900 adb push "$D/update_sd_ANE-L22J_hw_jp.zip" "$SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip" 2>&1 | tail -2

echo
echo "=== verify on device ==="
timeout 120 adb shell "ls -l $SD/update_sd.zip $SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip; echo; md5sum $SD/update_sd.zip $SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip"
echo "--- host:"
md5sum "$D/update_sd.zip" "$D/update_sd_ANE-L22J_hw_jp.zip"
