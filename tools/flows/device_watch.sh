#!/bin/bash
# Watch for the device to come back on its own.
#
# The phone is currently stuck mid-Android-boot (12d1:107e, only the MTP and Mass
# Storage interfaces, adb dead). It may recover by itself - a reboot loop that
# eventually lands in fastboot, or a watchdog reset - so log every USB transition
# with timestamps until it does, or until this exits.
set -u
LOG=/home/placeless/dev/p20-root/device_watch.log
: > "$LOG"
PREV=""
for i in $(seq 1 720); do
  USB=$(lsusb 2>/dev/null | grep -iE "12d1|18d1" | sed 's/.*ID //' | head -1)
  ADB=$(timeout 4 adb devices 2>/dev/null | awk 'NR==2{print $2}')
  FB=$(timeout 4 fastboot devices 2>/dev/null | awk '/fastboot/{print $1}')
  DEVNUM=$(lsusb 2>/dev/null | grep -iE "12d1|18d1" | grep -oE "Device [0-9]+" | head -1)
  CUR="$USB|$ADB|$FB|$DEVNUM"
  if [ "$CUR" != "$PREV" ]; then
    printf '%s  usb=%s adb=%s fastboot=%s %s\n' "$(date +%T)" "$USB" "$ADB" "$FB" "$DEVNUM" >> "$LOG"
    PREV="$CUR"
  fi
  sleep 25
done
