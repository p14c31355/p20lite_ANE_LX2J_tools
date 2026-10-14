#!/bin/bash
# Run the MMU-off framebuffer probe (fb2) and read the screen.
#
# Hypothesis under test: the loader enters our code but hands over with its MMU
# on, whose tables do not cover the regions a probe touches - so every earlier
# probe died on its first access. This build clears SCTLR.M first.
#
# Screen readout after the boot (watch ~2 minutes):
#   solid colour, then logo, then colour again   -> entered, and the MMU was the
#                                                   blocker: everything opens up
#   solid colour, then quiet (no logo loop)      -> entered; the SMC reset
#                                                   cannot reach EL3
#   nothing at all                               -> the loader is not entering
#                                                   our code (loading contract)
set -u
cd "$(dirname "$0")"
PROBE=artifacts/fullerene-ane-fb2.img
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
  echo "no fastboot after 40 min - hold Power ~10 s, then Volume Down + Power, then re-run"
  exit 1
fi

echo
echo "== flash the MMU-off framebuffer probe"
timeout 120 fastboot flash kernel "$PROBE" 2>&1 | tail -3

echo
echo "== boot it - WATCH THE SCREEN NOW (~2 minutes)"
timeout 30 fastboot reboot 2>&1 | head -1
echo
echo "   colour = entered + MMU was the blocker;  colour+logo loop = SMC also works"
echo "   nothing = the loader is not entering our code"
echo
python3 ane_usb_monitor.py --seconds 120 || true

echo
echo "== END OF WINDOW"
echo "   Press Volume Down + Power now for the stock restore (automatic)."
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
