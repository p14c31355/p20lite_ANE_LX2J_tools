#!/bin/bash
# L1 USB probe run: bring the USB2 controller up with the vendor's own
# bring-up sequence (clocks, abb, AHBIF, PHY resets, DCTL attach) and watch
# the host for an attach.
#
# The probe ends halted with the pull-up ON, so a successful attach is a
# STABLE device on the bus for inspection. The loader's own boot-failure
# fallback picks the device up after ~6-7 minutes of a hung boot, and this
# script's tail then restores the stock kernel on the next fastboot/adb
# appearance - no involvement needed until someone presses the buttons.
set -u
cd "$(dirname "$0")"
PROBE=artifacts/fullerene-ane-usb-l1.img

echo "== screen: keep it awake and bright (camera observation) =="
bash ane_screen_on.sh 2>&1 | tail -2 || true

echo "== waiting for a flashing route (adb -> bootloader, or fastboot)"
for i in $(seq 1 240); do
  timeout 6 fastboot devices 2>/dev/null | grep -q . && break
  if timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$"; then
    echo "adb is up -> rebooting to bootloader"
    timeout 30 adb reboot bootloader >/dev/null 2>&1
    sleep 5
    continue
  fi
  sleep 10
done
if ! timeout 6 fastboot devices 2>/dev/null | grep -q . ; then
  echo "no fastboot after 40 min"; exit 1
fi

echo "== flash the L1 USB probe ($PROBE)"
timeout 300 fastboot flash kernel "$PROBE" 2>&1 | tail -3

echo "== boot it: the host should see an attach built by the vendor sequence"
timeout 30 fastboot reboot 2>&1 | head -1
python3 ane_usb_monitor.py --seconds 480 || true

echo
echo "== host USB events now =="
timeout 60 sudo -n grep -E "usb 1-1" /var/log/kern.log 2>/dev/null | tail -20 | sed 's/.*kernel: //' || \
  echo "(kern.log needs a password; rely on the monitor timeline)"

echo
echo "== waiting for the next fastboot/adb appearance, then restoring (12h window)"
for hour in $(seq 1 1440); do
  if timeout 6 fastboot devices 2>/dev/null | grep -q . ; then
    echo "[$(date +%H:%M:%S)] fastboot is up -> restoring the stock kernel"
    timeout 300 fastboot flash kernel firmware/kernel_stock.bin 2>&1 | tail -2
    timeout 60 fastboot reboot 2>&1 | head -1
    for i in $(seq 1 120); do
      timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$" && { echo "[$(date +%H:%M:%S)] android is back"; break; }
      sleep 5
    done
    break
  fi
  if timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$"; then
    echo "[$(date +%H:%M:%S)] android is up"
    break
  fi
  sleep 30
done
echo "== L1 run complete =="
