#!/bin/bash
# Reboot and read the bootloader's own view of the lock state.
#
# FBLOCK lived in the nvme partition and read "locked (0x1)" before the write and
# "unlocked (0x0)" after, across all seven copies the tool found. The real proof is
# what the bootloader reports after a reboot:
#   - the kernel cmdline property ro.boot.flash.locked
#   - fastboot's FB LockState / Device unlocked fields
set -u
echo "############ rebooting"
timeout 60 adb reboot 2>&1
sleep 30

echo "############ waiting for the device to come back"
for i in $(seq 1 40); do
  ST=$(timeout 20 adb devices 2>/dev/null | awk 'NR==2{print $2}')
  echo "  adb: ${ST:-none}"
  [ "$ST" = "device" ] && break
  # a locked-bootloader state can show as unauthorized; keep waiting either way
  sleep 10
done

echo
echo "############ the properties the bootloader sets at boot"
timeout 40 adb shell 'getprop ro.boot.flash.locked; getprop ro.boot.verifiedbootstate; getprop ro.boot.veritymode; getprop ro.build.display.id; cat /proc/version' 2>&1

echo
echo "############ now ask the bootloader directly"
timeout 60 adb reboot bootloader 2>&1
sleep 25
echo "--- fastboot devices:"
timeout 60 fastboot devices 2>&1 | head -3
echo "--- lock state:"
timeout 90 fastboot oem getvar FB_LOCKSTATE 2>&1 | head -5
timeout 90 fastboot oem device-info 2>&1 | head -10
