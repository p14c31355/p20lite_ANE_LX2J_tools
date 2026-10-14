#!/bin/bash
# The decisive run: flash the reason probe and see whether the loader comes up
# in fastboot WITHOUT any button press.
#
# If it does, the mechanism is: the payload writes PMIC 0x18B = BOOTLOADER
# (0x01) through the MMIO window at 0xFFF34000, resets, and the loader reads
# the reason and enters fastboot. That makes every future cycle automatic:
# flash probe -> probe resets -> fastboot -> restore -> probe again.
#
# The tail then restores the stock kernel on the *next* fastboot/adb
# appearance - which, if the probe works, is the fastboot it just produced.
set -u
cd "$(dirname "$0")"
PROBE=artifacts/fullerene-ane-reason-probe.img

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

echo "== flash the reason probe ($PROBE)"
timeout 300 fastboot flash kernel "$PROBE" 2>&1 | tail -3

echo "== boot it. Expectation: the loader's warning appears, then the machine"
echo "   resets ONCE and comes up in FASTBOOT with no button press."
timeout 30 fastboot reboot 2>&1 | head -1
FB=""
for i in $(seq 1 45); do
  if timeout 6 fastboot devices 2>/dev/null | grep -q . ; then FB=yes; break; fi
  sleep 2
done
if [ -n "$FB" ]; then
  echo
  echo "================================================================"
  echo "  BREAKTHROUGH: fastboot came up with NO button press."
  echo "  The PMIC reason write works; button-free cycles exist."
  echo "================================================================"
else
  echo "== no fastboot within 90 s: the reason write did not take (or wrong"
  echo "   window/register). The probe's own SMC reset would loop it back."
fi

echo
echo "== restoring the stock kernel now (so the next boot is Android)"
for i in $(seq 1 40); do
  timeout 6 fastboot devices 2>/dev/null | grep -q . && break
  sleep 5
done
if timeout 6 fastboot devices 2>/dev/null | grep -q . ; then
  timeout 300 fastboot flash kernel firmware/kernel_stock.bin 2>&1 | tail -2
  timeout 60 fastboot reboot 2>&1 | head -1
  for i in $(seq 1 120); do
    timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$" && { echo "[$(date +%H:%M:%S)] android is back"; break; }
    sleep 5
  done
else
  echo "== no fastboot for the restore; the revive watcher owns the rescue case"
fi
echo "== reason probe run complete =="
