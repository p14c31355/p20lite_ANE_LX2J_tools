#!/bin/bash
# v7n: the scan base restored to FTLX_BASE with the MMU: anchor. This undoes
# the v7g regression (base moved to RAMO_WIN_START while the bound stayed
# 0xFFF0, so the scan never reached the log at 0x348D0000: it looked only at
# [0x34800000,0x3480FFF0), the ramoops header area). The reader is now
# identical in targeting to the v7f that worked at 20:37, with the anchor
# updated to a line every build prints.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V7N=artifacts/fullerene-ane-log-v7n-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for fastboot (combo) to flash v7n (fixed scan base)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v7n"
timeout 120 fastboot -s "$S" flash kernel "$V7N" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7N BOOTED - render in ~30-40 s; PHOTO NOW"
say "(expect: the real v17 log from MMU: IDENTITY MAP... with ud:/usb: rows)"
