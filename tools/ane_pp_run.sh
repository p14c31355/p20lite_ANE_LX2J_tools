#!/bin/bash
# Run the combined probe (pstore record + UART poke), then read the pstore back.
#
# Two questions in one cycle:
#   1. does the pstore channel work now that the MMU-off preamble is in place?
#      -> the readback must contain "\nP3:U" in pmsg-ramoops-0
#   2. is the PL011 write (the one Fullerene's console makes) fatal on device?
#      -> loop (warning repeats) = harmless; rescue ~30 s = fatal
set -u
cd "$(dirname "$0")"
PROBE=artifacts/fullerene-ane-pstore-poke.img
STOCK=firmware/kernel_stock.bin

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
  echo "no fastboot after 40 min - Volume Down + Power, then re-run"; exit 1
fi

echo
echo "== flash the combined probe"
timeout 300 fastboot flash kernel "$PROBE" 2>&1 | tail -3

echo
echo "== boot it - watch ~90 s (colour? loop? rescue?)"
timeout 30 fastboot reboot 2>&1 | head -1
python3 ane_usb_monitor.py --seconds 90 || true

echo
echo "== END OF WINDOW - press Volume Down + Power for the stock restore"
for i in $(seq 1 120); do
  timeout 6 fastboot devices 2>/dev/null | grep -q . && break
  sleep 10
done
if ! timeout 6 fastboot devices 2>/dev/null | grep -q . ; then
  echo "== fastboot never came; restore manually: fastboot flash kernel $STOCK"; exit 1
fi

echo "== restoring the stock kernel"
timeout 300 fastboot flash kernel "$STOCK" 2>&1 | tail -3
timeout 60 fastboot reboot 2>&1 | head -1
echo "== waiting for Android"
for i in $(seq 1 120); do
  timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$" && { echo "android is back"; break; }
  sleep 5
done

echo
echo "== pstore readback (the verdict on the record) =="
timeout 900 bash ane_read_pstore.sh 2>&1 | tail -50
