#!/bin/bash
# v17 -> v7k.
# v17: the v16 kernel plus a fingerprint write ("KRNL"/"ESET" at the private
# block's +0x20) planted right after our own identity map comes up.
# v7k: the v7h reader plus a ZK word in the ZH row, dumping that +0x20 word.
# One cycle answers: do the kernel's plain stores reach 0x348D0000 at all?
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V17=artifacts/fullerene-ane-v17-stock.img
V7K=artifacts/fullerene-ane-log-v7k-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
wait_fastboot(){ while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done; }

say "stage 1/2: waiting for fastboot (combo) to flash v17 (kernel fingerprint)"
wait_fastboot
say "FASTBOOT - flashing v17"
timeout 180 fastboot -s "$S" flash kernel "$V17" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V17 BOOTED - wait ~40 s then COMBO for stage 2"

say "stage 2/2: waiting for fastboot to flash v7k (reads the fingerprint)"
wait_fastboot
say "FASTBOOT - flashing v7k"
timeout 120 fastboot -s "$S" flash kernel "$V7K" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7K BOOTED - render in ~30-40 s; PHOTO NOW"
say "(ZK = 4B524E4C/45534554 = KRNL/ESET = kernel writes land; other = isolated)"
