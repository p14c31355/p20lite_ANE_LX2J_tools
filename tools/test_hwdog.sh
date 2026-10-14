#!/bin/bash
# Test the ANE factory-unlock fastboot command. Free, no root, no SELinux work.
#
#   fastboot oem hwdog certify set <0|1>
#
# Two sources disagree on the value that unlocks:
#   -Alf- (ANE authority): "This lock is controlled ... using the command
#          fastboot oem hwdog certify set <0 or 1>"
#   gr5-2017 video (Kirin 659): "fastboot oem hwdog certify set 1"
# hisi-nve's source defines FBLOCK 0 = unlocked, 1 = locked.
# So: try each value and read the bootloader's own lock-state report after each.
# A user reports the flip does not survive a reboot, which is fine - it only has
# to last long enough to flash.
#
# Deliberately NO flash attempt: a 0-byte flash could blank a partition.
set -u

echo "############ 1. lock state from Android"
timeout 30 adb shell 'getprop ro.boot.flash.locked; getprop ro.build.display.id' 2>&1

echo
echo "############ 2. reboot to the bootloader"
timeout 60 adb reboot bootloader 2>&1
for i in $(seq 1 30); do
  timeout 15 fastboot devices 2>/dev/null | grep -q . && { echo "  fastboot up after ${i}0s"; break; }
  sleep 10
done
timeout 20 fastboot devices 2>&1

echo
echo "############ 3. baseline"
timeout 40 fastboot oem lock-state info 2>&1 | head -8

echo
echo "############ 4. read-only capability probe"
timeout 40 fastboot getvar max-download-size 2>&1 | head -3
timeout 40 fastboot getvar product 2>&1 | head -3

echo
echo "############ 5. try the factory-unlock command, both values"
for V in 0 1; do
  echo "---- fastboot oem hwdog certify set $V"
  timeout 40 fastboot oem hwdog certify set $V 2>&1 | head -6
  echo "     lock state now:"
  timeout 40 fastboot oem lock-state info 2>&1 | head -6
done

echo
echo "############ 6. and the other spellings from the fastboot command dump"
for CMD in "oem hwdog certify begin" "oem hwdog certify close"; do
  echo "---- fastboot $CMD"
  timeout 40 fastboot $CMD 2>&1 | head -5
  timeout 40 fastboot oem lock-state info 2>&1 | head -6
done

echo
echo "############ 7. boot back to Android and confirm what persisted"
timeout 40 fastboot reboot 2>&1 | head -2
sleep 35
for i in $(seq 1 30); do
  [ "$(timeout 20 adb get-state 2>/dev/null | head -1)" = "device" ] && break
  sleep 10
done
timeout 30 adb shell 'getprop ro.boot.flash.locked; getprop ro.build.display.id' 2>&1
