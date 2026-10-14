#!/bin/bash
# SAFETY SELF-TEST: write the stock kernel back with fastboot.
#
# The image is identical to what is already there, so this changes nothing - but it
# proves three things we will depend on for the port:
#   1. the unlocked bootloader accepts `fastboot flash kernel`
#   2. the LK boots a kernel written this way
#   3. our recovery path (restore from a host-side image) works
#
# If this fails, nothing else in the plan is possible.
set -u
cd /home/placeless/dev/p20-root

echo "############ image to write"
ls -la firmware/kernel_stock.bin
md5sum firmware/kernel_stock.bin

echo
echo "############ into the bootloader"
timeout 60 adb reboot bootloader 2>&1 | head -1
for i in $(seq 1 20); do sleep 2; timeout 8 fastboot devices 2>/dev/null | grep -q . && break; done
timeout 15 fastboot devices 2>&1 | head -2

echo
echo "############ the lock state (must be unlocked for this to be allowed)"
timeout 40 fastboot oem lock-state info 2>&1 | head -3

echo
echo "############ write the stock kernel back"
timeout 300 fastboot flash kernel firmware/kernel_stock.bin 2>&1 | tail -6

echo
echo "############ reboot and see whether it comes back"
timeout 60 fastboot reboot 2>&1 | head -1
for i in $(seq 1 40); do
  ST=$(timeout 15 adb devices 2>/dev/null | awk 'NR==2{print $2}')
  if [ "$ST" = "device" ]; then
    echo "  back on adb after $((i*5))s"
    break
  fi
  sleep 5
done
echo
timeout 30 adb shell 'getprop ro.build.display.id; getprop ro.boot.flash.locked; cat /proc/version' 2>&1 | head -4
