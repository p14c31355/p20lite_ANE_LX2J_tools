#!/bin/bash
# USB probe run, autonomous end: flash, boot, watch the host USB log, end.
#
# The question this answers, and it is the one the whole self-drive hinges on:
# does the DWC2 core still drive the bus after the loader's handoff, once the
# MMU is cleared? If yes, the host sees attach/detach events built from OUR
# writes - the only observation channel that needs neither Android (which
# consumes pstore at boot) nor buttons.
#
# The device will end in the loader's own fallback (rescue screen, ~5 min);
# ane_catch_recover.sh is armed separately so any later button press restores
# the stock and reads the pstore without further involvement.
set -u
cd "$(dirname "$0")"
PROBE=artifacts/fullerene-ane-usb-probe.img

echo "== pre-run host USB event marker =="
date +%s > /tmp/usb_run_epoch.txt
MARK=$(cat /tmp/usb_run_epoch.txt)

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

echo "== flash the MMU-off USB probe ($PROBE)"
timeout 300 fastboot flash kernel "$PROBE" 2>&1 | tail -3

echo "== boot it: watch for attach/detach built from OUR DCTL writes"
timeout 30 fastboot reboot 2>&1 | head -1
python3 ane_usb_monitor.py --seconds 150 || true

echo
echo "== host USB events in this window (kern.log) =="
sudo grep -E "usb 1-1|USB disconnect" /var/log/kern.log | tail -40 | sed 's/.*kernel: //'

echo
echo "== done monitoring. The device is expected to sit in the loader fallback."
echo "== waiting for the next fastboot/adb appearance, then restoring (hours ok)"
for hour in $(seq 1 12); do
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
echo "== run2 complete =="
