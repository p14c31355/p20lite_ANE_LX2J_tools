#!/bin/bash
# v7f-only: the v10 boot of 20:23 already flushed its usb report into the
# durable block (tee_flush right after the report). The loader tramples only
# the block header, and the v7f's anchor scan ("USB: ABB=") is header-
# independent, so a single combo reaches the report.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V7F=artifacts/fullerene-ane-log-v7f-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "armed: ONE combo - waiting for fastboot to flash v7f"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done

say "FASTBOOT - flashing v7f (anchor scan: last 'USB: ABB=' -> render)"
timeout 120 fastboot -s "$S" flash kernel "$V7F" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7F BOOTED - render in ~30-40s; PHOTO NOW"
say "(expect: USB: ABB=... PPPLL0=...->... / USB: GUSBCFG=... / USB: PHY0=...)"
