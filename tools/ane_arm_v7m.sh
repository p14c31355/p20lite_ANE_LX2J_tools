#!/bin/bash
# v7m: the reader with the anchor changed from "USB: ABB=" (an ane_fb report
# line, absent since the fb was disabled at v13) to "MMU: " (the kernel's
# first console line in every build). The garbage renders since 20:46 were
# this stale anchor falling through to the offset-0 fallback - the log itself
# was landing all along (proven by the ZK word reading "ALU" at FTLX+0x4000).
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V7M=artifacts/fullerene-ane-log-v7m-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for fastboot (combo) to flash v7m (anchor = MMU:)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v7m"
timeout 120 fastboot -s "$S" flash kernel "$V7M" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7M BOOTED - render in ~30-40 s; PHOTO NOW"
say "(expect: the real v17 log from 'MMU: IDENTITY MAP...' - ud:/usb: rows)"
