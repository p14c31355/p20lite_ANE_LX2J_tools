#!/bin/bash
# Run the USB probe on the device and read both channels.
#
# Sequence: get to fastboot -> flash the probe -> reboot -> watch the host's USB
# log for 60 s (the DCTL pulse channel) -> wait for the user's buttons -> restore
# the stock kernel -> Android.
#
# Reading the run:
#   * host kern.log shows attach/detach events in pairs from OUR writes
#     -> the loader entered our code AND its USB core state is still usable
#   * the machine resets and re-runs the probe (screen flickers, and the
#     attach/detach pattern repeats every ~8 s)
#     -> the loader entered our code (independent of USB)
#   * neither -> the loader is not entering our code (loading contract problem)
set -u
cd "$(dirname "$0")"
PROBE=artifacts/fullerene-ane-usb-probe.img
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
echo "== flash the USB probe"
timeout 120 fastboot flash kernel "$PROBE" 2>&1 | tail -3

echo
echo "== boot it and watch the host's USB log for 60 s"
timeout 30 fastboot reboot 2>&1 | head -1
python3 ane_usb_monitor.py --seconds 60

echo
echo "== END OF WATCH WINDOW"
echo "   If the run showed reset loops, press Volume Down + Power now to stop"
echo "   them and enter fastboot. Waiting for fastboot (up to 15 min) to restore"
echo "   the stock kernel."
for i in $(seq 1 90); do
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
