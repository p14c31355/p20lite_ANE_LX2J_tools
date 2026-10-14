#!/bin/bash
# Restore the ORIGINAL, properly signed packages to the SD card.
#
# Rationale: normal_reset_type=ForceSdUpdate (a value update-binary reads from the
# misc partition) is the SD-update-allowed path, as opposed to VolUpRecovery which
# is what the 3-button combo sets and which runs sec_dld_main_version_check.
# If the ProjectMenu route really sets ForceSdUpdate, the stock package is both
# sufficient and preferable - untouched files mean Huawei's signature still
# verifies, so the 5% abort cannot be a package-integrity problem.
set -u
SRC=/tmp/fw3/Software/dload
SD=/storage/D4DD-4FB0/dload

echo "=== pushing ORIGINAL main package ==="
timeout 30 adb shell "rm -f $SD/update_sd.zip"
timeout 900 adb push "$SRC/update_sd.zip" "$SD/update_sd.zip" 2>&1 | tail -2

echo
echo "=== pushing ORIGINAL customized-data package ==="
timeout 30 adb shell "rm -f $SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip"
timeout 900 adb push "$SRC/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip" "$SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip" 2>&1 | tail -2

echo
echo "=== verify on device against the extracted originals ==="
timeout 120 adb shell "ls -l $SD/update_sd.zip $SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip; echo; md5sum $SD/update_sd.zip $SD/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip"
echo "--- expected (this is what the SD held before any of my edits):"
md5sum "$SRC/update_sd.zip" "$SRC/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip"
