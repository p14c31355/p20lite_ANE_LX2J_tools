#!/bin/bash
# v24: EP1 fixes (byte-exact collect, loader TXFNUM preserved, SETD0PID) plus
# the on-screen diag strip. The chain distinguishes the LK from our kernels by
# the USB product string, flashes, waits for the kernel, then probes EP1 with
# pyusb - the result lands in the terminal AND on the panel strip.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V24=artifacts/fullerene-ane-v24-stock.img
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

say "FASTBOOT - flashing v24"
timeout 180 fastboot -s "$S" flash kernel "$V24" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1

say "waiting for the v24 kernel (product 'ANE fastboot')"
P=""
for i in $(seq 1 24); do
  P=$(prod)
  if [ "$P" = "ANE fastboot" ]; then break; fi
  sleep 5
done
say "device product: ${P:-none}"
if [ "$P" != "ANE fastboot" ]; then say "KERNEL NOT SEEN - photo the screen"; exit 2; fi
sleep 5

say "PROBE: pyusb getvar:version against the running kernel"
uv run --no-project --with pyusb python3 probe_fb.py --nul 2>&1 | tail -6
say "DONE - photo the screen lower half (FB0..FB7) if the read failed"
