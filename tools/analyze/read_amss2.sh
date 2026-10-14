#!/bin/bash
# Complete the property sweep: find anything that looks like the device's own
# version identifiers, especially anything matching the ANNEC00B000 style used in
# SOFTWARE_VER_LIST.mbn (model codename + cust + min build).
set -u
echo "########## version-ish ro.* properties"
timeout 90 adb shell 'getprop | grep -E "^\[ro\." | grep -iE "ver|build|board|cust|hw|baseband" | head -60' 2>&1
echo
echo "########## anything with an ANNE / C6xx pattern"
timeout 90 adb shell 'getprop | grep -iE "anne|c6[0-9][0-9]|hi6250" | head -30' 2>&1
echo
echo "########## oeminfo-adjacent readable nodes"
timeout 60 adb shell 'ls -l /proc/oeminfo* /dev/block/by-name/oeminfo /dev/block/platform/*/by-name/oeminfo 2>&1 | head -5' 2>&1
echo
echo "########## can we see the board/version from cmdline or cpuinfo?"
timeout 60 adb shell 'cat /proc/cmdline 2>/dev/null | head -c 400; echo; echo "---"; head -20 /proc/cpuinfo' 2>&1
