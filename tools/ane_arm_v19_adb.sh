#!/bin/bash
# v19: full-screen fb (canvas in the DT graphic reserve) revived. No combo
# needed: the phone runs stock Android with adb, so adb drives both the
# bootloader reboot and (later) the log reads.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V19=artifacts/fullerene-ane-v19-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "adb: rebooting to the bootloader"
timeout 20 adb -s "$S" reboot bootloader >/dev/null 2>&1 || echo "(adb reboot failed - use combo if needed)"
say "waiting for fastboot"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v19"
timeout 180 fastboot -s "$S" flash kernel "$V19" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V19 BOOTED - full-screen report should appear within ~30 s; PHOTO NOW"
say "(expect: black screen covered, yellow report text, no loader warning)"
