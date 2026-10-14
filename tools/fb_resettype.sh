#!/bin/bash
# normal_reset_type lives in the misc partition and is normally written by the
# bootloader based on the key combination. If fastboot exposes any verb that sets
# it (or that reboots into a forced-SD-update mode), that is the lever.
# Availability only - nothing here writes anything.
set -u
echo "=== to bootloader ==="
adb reboot bootloader 2>&1
for i in $(seq 1 20); do sleep 2; timeout 10 fastboot devices 2>/dev/null | grep -q . && break; done
timeout 10 fastboot devices 2>&1
echo
run() { printf '%-46s : ' "$1"; timeout 20 fastboot $2 2>&1 | head -3 | tr '\n' ' '; echo; }

echo "########## reset-type / misc / update related verbs"
for v in \
  "oem set-reset-type ForceSdUpdate" \
  "oem normal_reset_type ForceSdUpdate" \
  "oem normal-reset-type ForceSdUpdate" \
  "oem force-sd-update" \
  "oem forcesdupdate" \
  "oem set-reset-type" \
  "oem misc" \
  "oem read-misc" \
  "oem write-misc" \
  "oem update" \
  "oem boot-recovery" \
  "oem reboot-recovery" \
  "oem enter-recovery" \
  "oem recovery" \
  "oem force-update" \
  "oem sd-update" \
  "oem usb-update" \
  ; do
  run "$v" "$v"
done

echo
echo "########## reboot to Android"
timeout 30 fastboot reboot 2>&1
sleep 30
timeout 20 adb devices -l 2>&1
