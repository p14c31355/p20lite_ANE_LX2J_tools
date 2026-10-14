#!/bin/bash
# v12: the first device-side build - EP0 control transfers + descriptors
# (fastboot-compatible interface). The visible milestone is host-side:
# the enumeration completes without the -110 descriptor timeouts.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V12=artifacts/fullerene-ane-v12-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "armed: waiting for fastboot to flash v12 (DWC2 device responder)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done

say "FASTBOOT - flashing v12"
timeout 180 fastboot -s "$S" flash kernel "$V12" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V12 BOOTED - host enumeration expected within ~20 s (check journal)"
say "(success = 'New USB device found' + 'Product: ANE fastboot' + no -110)"
