#!/bin/bash
# Can the bootloader still read/write NV properties for us?
#
# Earlier sweeps found `oem nve` = "Command not allowed". That was before FBLOCK was
# cleared and before OEM unlocking was enabled, so the allow-list may have changed.
# If it works now we can fix USRKEY from fastboot alone - no adb, no root, no exploit.
set -u
cd /home/placeless/dev/p20-root

echo "############ device"
timeout 15 fastboot devices 2>&1 | head -2
echo
echo "############ what NV-ish verbs exist?"
for V in \
  "oem nve" \
  "oem nve r USRKEY" \
  "oem nve read USRKEY" \
  "oem nve get USRKEY" \
  "oem read-nve USRKEY" \
  "oem get-nve USRKEY" \
  "oem nv-read USRKEY" \
  "oem readnv USRKEY" \
  "oem nvread USRKEY" \
  ; do
  printf '%-32s : ' "$V"
  timeout 25 fastboot $V 2>&1 | head -3 | tr '\n' ' '
  echo
done

echo
echo "############ the lock states, for reference"
timeout 30 fastboot oem lock-state info 2>&1 | head -3
echo
echo "############ help-ish verbs that might list commands"
for V in "oem help" "oem ?" "help"; do
  printf '%-32s : ' "$V"
  timeout 25 fastboot $V 2>&1 | head -6 | tr '\n' ' '
  echo
done
