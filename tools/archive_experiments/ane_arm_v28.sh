#!/bin/bash
# v28: paced `oem log` + reboot / reboot-bootloader via the PMIC reason
# register (BOOTLOADER=0x01). The chain ends with the full no-combo cycle:
# fastboot reboot-bootloader -> LK fastboot -> flash again -> kernel.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V28=artifacts/fullerene-ane-v28-stock.img
FASTBOOT=$(command -v fastboot || echo /usr/bin/fastboot)
say(){ echo "[$(date +%H:%M:%S)] $*"; }

prod(){ for f in /sys/bus/usb/devices/*/product; do
    d=$(dirname "$f")
    v=$(cat "$d/idVendor" 2>/dev/null); p=$(cat "$d/idProduct" 2>/dev/null)
    if [ "$v" = 18d1 ] && [ "$p" = d00d ]; then cat "$f"; return; fi
  done; }

say "COMBO now - waiting for the LK (product 'Fastboot2.0'), up to 4 min"
P=""
for i in $(seq 1 48); do
  P=$(prod)
  if [ "$P" = "Fastboot2.0" ]; then break; fi
  sleep 5
done
say "device product: ${P:-none}"
if [ "$P" != "Fastboot2.0" ]; then say "LK NOT SEEN - abort"; exit 1; fi

say "FASTBOOT - flashing v28"
timeout 180 "$FASTBOOT" -s "$S" flash kernel "$V28" 2>&1 | tail -2
timeout 60 "$FASTBOOT" -s "$S" reboot 2>&1 | tail -1

say "waiting for the v28 kernel (product 'ANE fastboot')"
P=""
for i in $(seq 1 24); do
  P=$(prod)
  if [ "$P" = "ANE fastboot" ]; then break; fi
  sleep 5
done
say "device product: ${P:-none}"
if [ "$P" != "ANE fastboot" ]; then say "KERNEL NOT SEEN - photo the screen"; exit 2; fi
sleep 5

say "TEST 1: getvar version"
timeout 15 "$FASTBOOT" -s "$S" getvar version 2>&1 | tail -2
say "TEST 2: oem log (paced, expect many lines + clean finish)"
timeout 30 "$FASTBOOT" -s "$S" oem log 2>&1 | tail -12
say "TEST 3: reboot-bootloader (THE no-combo test)"
timeout 20 "$FASTBOOT" -s "$S" reboot-bootloader 2>&1 | tail -2

say "waiting for the LK WITHOUT a combo (up to 90 s)"
P=""
for i in $(seq 1 18); do
  P=$(prod)
  if [ "$P" = "Fastboot2.0" ]; then break; fi
  sleep 5
done
say "device product: ${P:-none}"
if [ "$P" = "Fastboot2.0" ]; then
  say "NO-COMBO FASTBOOT REACHED - flashing v28 back to prove the loop"
  timeout 180 "$FASTBOOT" -s "$S" flash kernel "$V28" 2>&1 | tail -2
  timeout 60 "$FASTBOOT" -s "$S" reboot 2>&1 | tail -1
  P=""
  for i in $(seq 1 24); do
    P=$(prod)
    if [ "$P" = "ANE fastboot" ]; then break; fi
    sleep 5
  done
  say "device product: ${P:-none}"
  if [ "$P" = "ANE fastboot" ]; then
    say "TEST 4: getvar version after the full no-combo loop"
    timeout 15 "$FASTBOOT" -s "$S" getvar version 2>&1 | tail -2
  fi
else
  say "LK NOT REACHED via reboot-bootloader (device: ${P:-none})"
fi
say "DONE"
