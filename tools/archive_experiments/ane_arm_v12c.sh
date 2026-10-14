#!/bin/bash
# v12c: the EP0 responder with the vendor's exact setup-arm values
# (dwc_otg_pcd_intr.c ep0_out_start: supcnt=3, pktcnt=1, xfersize=24,
# CNAK cleared only after the setup interrupt).
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V12C=artifacts/fullerene-ane-v12c-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "armed: waiting for fastboot to flash v12c (vendor setup-arm values)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done

say "FASTBOOT - flashing v12c"
timeout 180 fastboot -s "$S" flash kernel "$V12C" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V12C BOOTED - host enumeration expected within ~25 s (journal check)"
say "(success = 'New USB device found' + 'Product: ANE fastboot' + no -110)"
