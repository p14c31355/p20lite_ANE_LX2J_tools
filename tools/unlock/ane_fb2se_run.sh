#!/bin/bash
# Same proven fb2 payload, but in the stock-embedded packaging.
#
# One variable changes against the tiny-image run that looped: the form. If
# this loops (unlocked warning repeating, colour while the probe holds), the
# stock-embedded form runs and Fullerene's own early path is the thing that
# died. If it rescues like Fullerene did, the form itself is the problem.
#
# Android is up, so entry is automatic (adb reboot bootloader) - no buttons
# until the observation window ends.
set -u
cd "$(dirname "$0")"
PROBE=artifacts/fb2-stock-embed.img
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
  echo "no fastboot after 40 min - Volume Down + Power, then re-run"
  exit 1
fi

echo
echo "== flash fb2 in the stock-embedded form (11.7 MB)"
timeout 300 fastboot flash kernel "$PROBE" 2>&1 | tail -3

echo
echo "== boot it - watch the screen"
timeout 30 fastboot reboot 2>&1 | head -1
python3 ane_usb_monitor.py --seconds 150 || true

echo
echo "== END OF WINDOW - press Volume Down + Power for the stock restore"
for i in $(seq 1 120); do
  timeout 6 fastboot devices 2>/dev/null | grep -q . && break
  sleep 10
done

if timeout 6 fastboot devices 2>/dev/null | grep -q .; then
  echo "== restoring the stock kernel"
  timeout 300 fastboot flash kernel "$STOCK" 2>&1 | tail -3
  timeout 60 fastboot reboot 2>&1 | head -1
  echo "== waiting for Android"
  for i in $(seq 1 120); do
    timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$" && { echo "android is back"; break; }
    sleep 5
  done
else
  echo "== fastboot never came; restore manually:"
  echo "   fastboot flash kernel $STOCK && fastboot reboot"
fi
