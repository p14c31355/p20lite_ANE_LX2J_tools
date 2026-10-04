#!/bin/bash
# Run the stock-embedded RCH probe: read the display's real scan addresses and
# colour each candidate, then loop.
#
# Why now: Fullerene's first stock-embedded run ended in rescue within ~30 s.
# This probe uses the same packaging with a payload whose behaviour is already
# proven (the fb2 fill+reset loop), so it separates "the stock-embedded form
# does not actually run" from "Fullerene itself died". Either way the colour
# that appears (if any) names the buffer the panel scans:
#   green=VG0, blue=VG1, red=G0, cyan=G1, magenta=0x31000000 fallback.
set -u
cd "$(dirname "$0")"
PROBE=artifacts/fullerene-ane-rch-probe.img
STOCK=firmware/kernel_stock.bin

echo "== waiting for fastboot (Volume Down + Power)"
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
if ! timeout 6 fastboot devices 2>/dev/null | grep -q .; then
  echo "no fastboot after 40 min - hold Power ~10 s, then Volume Down + Power"
  exit 1
fi

echo
echo "== flash the RCH probe (stock-embedded, 11.6 MB)"
timeout 300 fastboot flash kernel "$PROBE" 2>&1 | tail -3

echo
echo "== boot it - WATCH THE SCREEN (which colour, if any)"
timeout 30 fastboot reboot 2>&1 | head -1
python3 ane_usb_monitor.py --seconds 120 || true

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
