#!/bin/bash
# v25: dispatch on transfer boundary (no NUL assumption - the real client
# sends none), first-NUL parsing, padded TX sizes. The chain flashes through
# the LK and then runs THE REAL FASTBOOT CLIENT against the running kernel.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V25=artifacts/fullerene-ane-v25-stock.img
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

say "FASTBOOT - flashing v25"
timeout 180 "$FASTBOOT" -s "$S" flash kernel "$V25" 2>&1 | tail -2
timeout 60 "$FASTBOOT" -s "$S" reboot 2>&1 | tail -1

say "waiting for the v25 kernel (product 'ANE fastboot')"
P=""
for i in $(seq 1 24); do
  P=$(prod)
  if [ "$P" = "ANE fastboot" ]; then break; fi
  sleep 5
done
say "device product: ${P:-none}"
if [ "$P" != "ANE fastboot" ]; then say "KERNEL NOT SEEN - photo the screen"; exit 2; fi
sleep 5

say "REAL FASTBOOT TEST 1: getvar version"
timeout 15 "$FASTBOOT" -s "$S" getvar version 2>&1 | tail -2
say "REAL FASTBOOT TEST 2: getvar product"
timeout 15 "$FASTBOOT" -s "$S" getvar product 2>&1 | tail -2
say "REAL FASTBOOT TEST 3: getvar serialno"
timeout 15 "$FASTBOOT" -s "$S" getvar serialno 2>&1 | tail -2
say "DONE"
