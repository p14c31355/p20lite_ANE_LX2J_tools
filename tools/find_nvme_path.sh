#!/bin/bash
# What block devices can the shell see, and what is the nvme partition called?
# Needed for the last step: hisi-nve writes FBLOCK by opening the raw partition,
# so we must know its real path on this device.
set -u
echo "############ /proc/partitions (readable without SELinux help)"
timeout 30 adb shell 'cat /proc/partitions' 2>&1 | head -40
echo
echo "############ /dev/block top level"
timeout 30 adb shell 'ls -la /dev/block/' 2>&1 | head -25
echo
echo "############ platform by-name (if it exists)"
timeout 30 adb shell 'ls -la /dev/block/platform/ 2>&1; echo ---; ls -la /dev/block/platform/*/by-name/ 2>&1 | head -40' 2>&1 | head -60
echo
echo "############ what hisi-nve expects (from its source)"
grep -rnE "by-name|/dev/block|nvme" /home/placeless/dev/hisi-nve/src/nve/hisi_nve.c 2>/dev/null | head -20
