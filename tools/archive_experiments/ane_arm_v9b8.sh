#!/bin/bash
# v9: the self-reporting USB bring-up. One flash. Fullerene itself runs the
# vendor USB sequence (platform::ane::usb_bringup) and prints the readbacks
# on the screen console in the same boot - no cross-boot handoff, which the
# loader's per-boot DRAM re-initialisation makes impossible.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V9=artifacts/fullerene-ane-v9b8-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "armed: waiting for fastboot to flash v9b6 (single SCTRL read + render)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done

say "FASTBOOT - flashing v9 (11.4MB stock-shaped)"
timeout 180 fastboot -s "$S" flash kernel "$V9" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V9 BOOTED - render+attach = PMIC not needed; render only = PMIC needed for USB; blank = later hang; PHOTO NOW"
say "(expected: render visible; if blank, the abb/PMIC path is the hang)"
