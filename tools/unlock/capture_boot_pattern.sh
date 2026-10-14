#!/bin/bash
# Capture the USB enumeration pattern across a boot.
#
# This is our observation channel for unattended tests: nobody is awake to watch
# the screen, but the host can see exactly what the device puts on the bus and
# when. Recorded first for the STOCK kernel as a control; any later flash is
# compared against this.
set -u
cd /home/placeless/dev/p20-root
OUT=${1:-firmware/boot_pattern_stock.txt}
LABEL=${2:-stock}

echo "############ rebooting and watching the bus for 90s  ($LABEL)"
timeout 60 adb reboot 2>&1 | head -1 || true
: > "$OUT"
for i in $(seq 1 45); do
  T=$(date +%s.%N)
  USB=$(lsusb 2>/dev/null | grep -iE "12d1|18d1|1234" | head -2 | tr '\n' ';')
  FB=$(timeout 3 fastboot devices 2>/dev/null | head -1 | tr '\n' ' ')
  AD=$(timeout 3 adb devices 2>/dev/null | awk 'NR==2{print $1" "$2}')
  printf '%3d  %s  usb=[%s]  fastboot=[%s]  adb=[%s]\n' "$i" "$(date +%T)" "$USB" "$FB" "$AD" >> "$OUT"
  sleep 2
done
echo "--- pattern:"
cat "$OUT"
echo
echo "############ summary of states seen"
grep -oE "usb=\[[^]]*\]" "$OUT" | sort | uniq -c | sort -rn
