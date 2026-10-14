#!/bin/bash
# The moment of truth: which build and which kernel is the device running now?
#   Android 8.0.0.110  -> kernel 4.4.23  -> CVE-2019-2215 applies
#   Android 9.1.0.132  -> kernel 4.9.148 -> unchanged, update did not take
set -u
echo "=== device present? ==="
timeout 40 adb devices -l 2>&1
echo
echo "=== build identity ==="
timeout 40 adb shell 'getprop ro.build.display.id; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.build.version.incremental; getprop ro.product.model' 2>&1
echo
echo "=== kernel (the decisive line) ==="
timeout 40 adb shell 'cat /proc/version' 2>&1
echo
echo "=== how long has it been up (did it just reboot?) ==="
timeout 40 adb shell 'uptime; cat /proc/uptime' 2>&1
echo
echo "=== is the exploit's prerequisite present? (/dev/binder etc) ==="
timeout 40 adb shell 'ls -l /dev/binder /dev/hwbinder /dev/vndbinder 2>&1 | head -5' 2>&1
