#!/bin/bash
# Run the stock-payload probe: the stock kernel Image with our probe written at
# the stock's own entry point, so it passes whatever the LK checks (it IS the
# stock, same size, same header) and lands in our code either way the loader
# picks the entry.
#
# Screen readout (watch ~2.5 minutes):
#   solid colour (~40 s)             -> the loader entered our code and the
#                                       MMU/framebuffer path works
#   colour -> logo -> colour (loop)  -> PSCI reset works too
#   rescue/recovery UI again         -> the loader rejected even this, i.e. the
#                                       wall is somewhere else entirely
set -u
cd "$(dirname "$0")"
PROBE=artifacts/fullerene-ane-stockprobe.img
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
echo "== flash the stock-payload probe (11.7 MB, same shape as the accepted repack)"
timeout 300 fastboot flash kernel "$PROBE" 2>&1 | tail -3

echo
echo "== boot it - WATCH THE SCREEN NOW"
timeout 30 fastboot reboot 2>&1 | head -1
python3 ane_usb_monitor.py --seconds 150 || true

echo
echo "== END OF WINDOW - press Volume Down + Power for the automatic stock restore"
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
