#!/bin/bash
# Long-horizon catcher: whenever the device becomes reachable again (the user
# presses Volume Down + Power, or anything else lands us on fastboot/adb),
# restore the stock kernel, bring Android back, and read the pstore.
#
# Started 2026-10-02 ~09:20 while the pp probe was looping on the device. The
# loop cannot be interrupted from the host (no USB at all during the reset
# loop), so this script simply waits - hours if need be - and then does the
# whole recovery unattended.
set -u
cd "$(dirname "$0")"
STOCK=firmware/kernel_stock.bin

say() { echo "[$(date +%H:%M:%S)] $*"; }

for hour in $(seq 1 12); do
  # already in fastboot -> restore
  if timeout 6 fastboot devices 2>/dev/null | grep -q . ; then
    say "fastboot is up -> restoring the stock kernel"
    timeout 300 fastboot flash kernel "$STOCK" 2>&1 | tail -2
    timeout 60 fastboot reboot 2>&1 | head -1
    say "waiting for Android to finish booting (up to 10 minutes)"
    for i in $(seq 1 120); do
      timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$" && { say "android is up"; break; }
      sleep 5
    done
    break
  fi
  # Android up (e.g. someone held power and it booted normally, or a previous
  # restore already finished) -> make sure the kernel partition is stock, then
  # finish with the readback
  if timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$"; then
    say "android is up"
    break
  fi
  sleep 30
done

if timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$"; then
  say "waiting for the boot to settle"
  sleep 20
  say "== pstore readback =="
  timeout 900 bash ane_read_pstore.sh 2>&1 | tail -60
else
  say "device never came back within the catcher window - re-run when it does"
fi
