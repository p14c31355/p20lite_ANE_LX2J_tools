#!/bin/bash
# 1) Inspect the customized-data package for its own SOFTWARE_VER_LIST.mbn.
# 2) Patch it the same way if present.
# 3) Push both patched files onto the SD card over adb.
set -u
INNER=/tmp/fw3/Software/dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip
OUTD=/home/placeless/dev/p20-root/firmware/patched
SDDIR=/storage/D4DD-4FB0/dload

echo "=== has the inner customized package got its own version list? ==="
unzip -l "$INNER" 2>/dev/null | head -20
echo
echo "--- SOFTWARE_VER_LIST.mbn inside the inner package:"
unzip -p "$INNER" SOFTWARE_VER_LIST.mbn 2>/dev/null || echo "(no such entry)"

echo
echo "=== pushing the patched MAIN package to the SD card ==="
timeout 30 adb shell "ls -ld $SDDIR"
timeout 30 adb shell "rm -f $SDDIR/update_sd.zip" 2>&1
timeout 900 adb push "$OUTD/update_sd.zip" "$SDDIR/update_sd.zip" 2>&1 | tail -3

echo
echo "=== verify what landed ==="
timeout 60 adb shell "ls -l $SDDIR/update_sd.zip; echo; md5sum $SDDIR/update_sd.zip 2>/dev/null || echo '(no md5sum on device)'"
echo "--- host md5 for comparison:"
md5sum "$OUTD/update_sd.zip"
