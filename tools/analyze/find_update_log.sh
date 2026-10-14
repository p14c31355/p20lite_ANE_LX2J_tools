#!/bin/bash
# The updater logs everything with an "SDLOG:" prefix. Find what it left behind -
# it will say exactly which stage refused.
set -u
echo "########## recovery / update logs"
timeout 60 adb shell 'ls -la /cache/recovery/ 2>&1 | head -20' 
echo "--- /cache root:"
timeout 60 adb shell 'ls -la /cache/ 2>&1 | head -25'
echo
echo "########## update staging dirs"
for d in /data/update /data/update/dload /data/cache /sdcard/dload /sdcard/update; do
  echo "--- $d"
  timeout 60 adb shell "ls -la $d 2>&1 | head -12"
done
echo
echo "########## anything named like a log, recently modified, in the usual places"
timeout 90 adb shell 'ls -lat /sdcard/ 2>/dev/null | head -15'
echo
echo "########## SD card root, newest first"
timeout 60 adb shell 'ls -lat /storage/D4DD-4FB0/ 2>&1 | head -15'
