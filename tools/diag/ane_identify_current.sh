#!/bin/bash
# Identify what is actually running on the device right now.
#
# The open question: after the last fastboot session, is the kernel partition
# holding my probe, or the stock kernel? Android enumerating is only consistent
# with a bootable kernel, but "the recovery partition booted instead" is also
# possible. Two facts settle it:
#   1. /proc/version        -> which kernel is executing
#   2. the kernel partition -> hash-compare against every image we have built
#      (needs root; if the exploit path is up, this works)
set -u
cd "$(dirname "$0")"

echo "== waiting for adb (up to 25 min)"
for i in $(seq 1 300); do
  timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$" && break
  sleep 5
done
if ! timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$"; then
  echo "adb never came up"; exit 1
fi
echo "adb is up"

echo
echo "== /proc/version (the truth about the running kernel)"
timeout 10 adb shell cat /proc/version 2>&1 | head -2

echo
echo "== bootloader state"
for p in ro.boot.flash.locked ro.boot.verifiedbootstate ro.boot.slot_suffix; do
  timeout 5 adb shell getprop $p 2>/dev/null
done

echo
echo "== kernel partition vs every artifact (needs root)"
timeout 20 adb root >/dev/null 2>&1; sleep 3
timeout 10 adb wait-for-device 2>/dev/null
timeout 10 adb shell "ls -la /dev/block/by-name/kernel 2>/dev/null || ls -la /dev/block/bootdevice/by-name/kernel 2>/dev/null" 2>&1 | head -2
KP=$(timeout 10 adb shell "ls /dev/block/by-name/kernel /dev/block/bootdevice/by-name/kernel /dev/block/platform/*/by-name/kernel 2>/dev/null | head -1" 2>/dev/null | tr -d '\r')
if [ -n "$KP" ]; then
  echo "kernel partition: $KP"
  # dump the first 8 MiB (our images are far smaller; the stock is 24 MiB so also
  # grab a middle sample) and hash both windows
  timeout 120 adb shell "dd if=$KP of=/data/local/tmp/kp_head.bin bs=4096 count=2048 2>/dev/null" 
  timeout 120 adb shell "dd if=$KP of=/data/local/tmp/kp_tail.bin bs=4096 skip=5120 count=1024 2>/dev/null"
  timeout 60 adb pull /data/local/tmp/kp_head.bin /tmp/kp_head.bin >/dev/null 2>&1
  timeout 60 adb pull /data/local/tmp/kp_tail.bin /tmp/kp_tail.bin >/dev/null 2>&1
  for f in /tmp/kp_head.bin /tmp/kp_tail.bin; do
    [ -f "$f" ] && echo "  $(basename $f): md5=$(md5sum < "$f" | cut -d' ' -f1) size=$(stat -c %s "$f")"
  done
  echo
  echo "  candidate match (head 8MiB window):"
  for img in firmware/kernel_stock.bin artifacts/fullerene-ane-reset.img artifacts/fullerene-ane-mark2.img artifacts/fullerene-ane-mark.img; do
    [ -f "$img" ] || continue
    h=$(head -c 8388608 "$img" | md5sum | cut -d' ' -f1)
    printf "    %-40s %s\n" "$img" "$h"
  done
else
  echo "  (no root shell: kernel partition not readable - /proc/version is the fallback answer)"
fi

echo
echo "== pstore re-check (any channels alive?)"
timeout 30 bash ane_read_pstore.sh 2>&1 | tail -12
