#!/bin/bash
# v22: EP1 TX FIFO slot set (TXFNUM=1), IN size fixed (DIEPTSIZ1), and the
# bulk pair is activated on SET_CONFIGURATION like a gadget driver. Combo now;
# the LK appears; flash; boot; the getvar tests then hit the v22 responder.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V22=artifacts/fullerene-ane-v22-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "COMBO now: wait 25 s, then the LK"
sleep 25
say "waiting for fastboot (LK)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v22"
timeout 180 fastboot -s "$S" flash kernel "$V22" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V22 BOOTED - waiting 45 s"
sleep 45

say "TEST 1: getvar version"
timeout 20 fastboot -s "$S" getvar version 2>&1 | tail -3
say "TEST 2: getvar product"
timeout 20 fastboot -s "$S" getvar product 2>&1 | tail -3
say "DONE - expect 'version: 0.4' / 'product: ANE-LX2J' from the v22 kernel"
