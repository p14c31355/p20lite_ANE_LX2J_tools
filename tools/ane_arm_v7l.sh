#!/bin/bash
# v7l: the v7k reader with the ZK word pointed at FTLX+0x4000 - the fixed,
# header-independent log copy the kernel appends per boot (blackbox
# FIXED_LOG_OFF), which is outside the main block's text area and cannot be
# overwritten by log traffic. ASCII there ("4D4D553A" = "MMU:") proves the
# kernel's stores reach the block; junk proves they do not.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V7L=artifacts/fullerene-ane-log-v7l-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for fastboot (combo) to flash v7l (ZK now reads FTLX+0x4000)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v7l"
timeout 120 fastboot -s "$S" flash kernel "$V7L" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7L BOOTED - render in ~30-40 s; PHOTO NOW"
say "(ZK = readable ASCII like 4D4D553A = kernel log lands in the fixed copy)"
