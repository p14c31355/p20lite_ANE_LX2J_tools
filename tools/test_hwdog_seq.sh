#!/bin/bash
# The bootloader knows `oem hwdog certify` and answered `certify begin` with a
# FBLOCK hash. `certify set 0/1` was refused with "fb lockstat not unlocked",
# which looks like an ordering requirement rather than a hard denial - the
# command dump shows `certify begin` used as a sequence step before others.
# So: dump the bootloader's own command list, then try begin -> set.
set -u

echo "############ 1. reboot to the bootloader"
timeout 60 adb reboot bootloader 2>&1
for i in $(seq 1 30); do
  timeout 15 fastboot devices 2>/dev/null | grep -q . && { echo "  fastboot up"; break; }
  sleep 10
done
timeout 20 fastboot devices 2>&1

echo
echo "############ 2. baseline lock state"
timeout 40 fastboot oem lock-state info 2>&1 | head -6

echo
echo "############ 3. the bootloader's own command list (if it exposes one)"
for C in "oem help" "help" "oem ?" "oem list" "getvar all"; do
  echo "---- fastboot $C"
  timeout 30 fastboot $C 2>&1 | head -25
done

echo
echo "############ 4. begin first, then set"
echo "---- certify begin"
timeout 40 fastboot oem hwdog certify begin 2>&1 | head -4
echo "     lock state after begin:"
timeout 40 fastboot oem lock-state info 2>&1 | head -6

for V in 0 1; do
  echo "---- certify set $V (after begin)"
  timeout 40 fastboot oem hwdog certify set $V 2>&1 | head -4
  echo "     lock state:"
  timeout 40 fastboot oem lock-state info 2>&1 | head -6
done

echo
echo "############ 5. what does certify report now"
timeout 40 fastboot oem hwdog certify begin 2>&1 | head -4

echo
echo "############ 6. back to Android"
timeout 40 fastboot reboot 2>&1 | head -2
sleep 35
for i in $(seq 1 30); do
  [ "$(timeout 20 adb get-state 2>/dev/null | head -1)" = "device" ] && break
  sleep 10
done
timeout 30 adb shell 'getprop ro.boot.flash.locked' 2>&1
