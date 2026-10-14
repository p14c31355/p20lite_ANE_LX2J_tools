#!/bin/bash
# Run Fullerene itself on the ANE-LX2J, then read back its blackbox.
#
# What is proven going into this run (2026-10-02):
#   * the LK does enter our code - the fb2 probe's PSCI reset produced a visible
#     reset loop with the stock image shape exactly like this one;
#   * earlier probes died because the LK hands over with the MMU on and its
#     tables do not cover the kernel's reserved regions, so the first memory
#     access faulted into rescue. Fullerene's entry now clears SCTLR.M first
#     (entry.rs), and this run is the same stock-embedded shape that looped.
#
# The cycle: flash -> boot (Fullerene runs its ANE path and writes the ramoops
# blackbox) -> user stops it -> stock restore -> Android -> pstore readback,
# which is where Fullerene's first output on this device should appear.
set -u
cd "$(dirname "$0")"
PROBE=artifacts/fullerene-ane-stock-embed.img
STOCK=firmware/kernel_stock.bin

echo "== waiting for fastboot (Volume Down + Power to stop the loop / enter it)"
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
echo "== flash Fullerene (stock-embedded shape, 11.6 MB)"
timeout 300 fastboot flash kernel "$PROBE" 2>&1 | tail -3

echo
echo "== boot it - Fullerene gets the machine now"
timeout 30 fastboot reboot 2>&1 | head -1
python3 ane_usb_monitor.py --seconds 180 || true

echo
echo "== END OF WINDOW - press Volume Down + Power for the stock restore"
for i in $(seq 1 120); do
  timeout 6 fastboot devices 2>/dev/null | grep -q . && break
  sleep 10
done

if ! timeout 6 fastboot devices 2>/dev/null | grep -q .; then
  echo "== fastboot never came; restore manually: fastboot flash kernel $STOCK"
  exit 1
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
echo "== pstore readback (Fullerene's blackbox on the ANE - the first output)"
timeout 900 bash ane_read_pstore.sh 2>&1 | tail -45
