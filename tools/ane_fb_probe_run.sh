#!/bin/bash
# Run the framebuffer probe: the screen itself is the readout.
#
# Sequence: fastboot -> flash the probe -> reboot -> the user watches the screen
# for 90 s -> then Volume Down + Power -> stock restore -> Android.
#
# What the screen should show if the loader entered our code:
#   solid colour (~25 s) -> logo -> solid colour -> logo -> ...   (a loop)
# If the colour never appears, the loader is not entering our code.
set -u
cd "$(dirname "$0")"
PROBE=artifacts/fullerene-ane-fb-probe.img
STOCK=firmware/kernel_stock.bin

echo "== waiting for a flashing route (fastboot, or adb to reboot into it)"
for i in $(seq 1 240); do
  if timeout 6 fastboot devices 2>/dev/null | grep -q .; then
    echo "fastboot is up"; break
  fi
  if timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$"; then
    echo "adb is up -> rebooting to bootloader"
    timeout 30 adb reboot bootloader >/dev/null 2>&1
    sleep 5
    continue
  fi
  sleep 10
done
if ! timeout 6 fastboot devices 2>/dev/null | grep -q .; then
  echo "no fastboot after 40 min - press Volume Down + Power on the device, then re-run"
  exit 1
fi

echo
echo "== flash the framebuffer probe"
timeout 120 fastboot flash kernel "$PROBE" 2>&1 | tail -3

echo
echo "== boot it - WATCH THE SCREEN NOW"
timeout 30 fastboot reboot 2>&1 | head -1
echo
echo "   expected if the loader enters our code:"
echo "     solid colour for ~25 s, then logo, then colour again (a loop)"
echo "   nothing at all: the loader is not entering our code"
echo
echo "== host-side record for these 90 s (should stay dark either way)"
python3 ane_usb_monitor.py --seconds 90 || true

echo
echo "== END OF WINDOW"
echo "   Press Volume Down + Power now to enter fastboot; the stock kernel will"
echo "   be restored automatically when fastboot appears."
for i in $(seq 1 120); do
  timeout 6 fastboot devices 2>/dev/null | grep -q . && break
  sleep 10
done

if timeout 6 fastboot devices 2>/dev/null | grep -q .; then
  echo "== restoring the stock kernel"
  timeout 300 fastboot flash kernel "$STOCK" 2>&1 | tail -3
  timeout 60 fastboot reboot 2>&1 | head -1
  echo "== waiting for Android"
  for i in $(seq 1 60); do
    timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$" && { echo "android is back"; break; }
    sleep 5
  done
else
  echo "== fastboot never came; restore manually:"
  echo "   fastboot flash kernel $STOCK && fastboot reboot"
fi
