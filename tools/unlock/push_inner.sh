#!/bin/bash
# Safety gate for the inner package, then push it to the SD card.
set -u
A=/tmp/fw3/Software/dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip
B=/home/placeless/dev/p20-root/firmware/patched/update_sd_ANE-L22J_hw_jp.zip
SDDIR=/storage/D4DD-4FB0/dload

echo "=== payload must be byte-identical ==="
for z in "$A" "$B"; do
  printf '%-30s : ' "$(basename $z)"
  unzip -p "$z" update_ANE-L22J_hw_jp.app 2>/dev/null | md5sum | awk '{print $1}'
done

echo
echo "=== push to the SD card ==="
timeout 30 adb shell "rm -f $SDDIR/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip"
timeout 900 adb push "$B" "$SDDIR/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip" 2>&1 | tail -2

echo
echo "=== what is on the card now ==="
timeout 60 adb shell "ls -l $SDDIR/update_sd.zip $SDDIR/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip; echo; md5sum $SDDIR/update_sd.zip $SDDIR/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip"
echo "--- host md5 for comparison:"
md5sum "$B"
