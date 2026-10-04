#!/usr/bin/env bash
# Set the BCB to "bootloader" at the next fastboot moment.
#
# Why: the nightly loop's restores used to end by booting Android, which on
# this device is a slow EMUI boot that sometimes freezes mid-boot (2-interface
# hang) and always needs the user's hands to leave. With the BCB command at
# the start of misc set to "bootloader", every reset lands back in fastboot
# instead: the phone never boots EMUI during the loop. The stock kernel still
# gets flashed at each restore, so the recovery path stays validated.
#
# The BCB is a toggle, not a one-way switch - fire_probe() in the runner
# clears it again before each probe (otherwise the probe's reboot would park
# in fastboot instead of running the probe), and release_to_android() clears
# it at the wind-down so the phone boots Android for the user in the morning.
#
# This script only needs to win ONCE: after it lands, the runner's own
# restore_stock() keeps re-arming the BCB at every restore. It waits for the
# fastboot moment (the user's Volume Down + Power combo), flashes, verifies
# OKAY, then exits.
set -u
cd "$(dirname "$0")"
LOG=usb_runs/bcb_hold.log
mkdir -p usb_runs

say() { echo "$(date '+%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }

say "armed: waiting for fastboot to set BCB=bootloader"
for i in $(seq 1 360); do   # up to ~6h at 60s intervals
  if timeout 20 fastboot devices 2>/dev/null | grep -q .; then
    out=$(timeout 60 fastboot flash misc firmware/misc_bootloader.img 2>&1)
    if echo "$out" | grep -q "OKAY"; then
      say "BCB set to bootloader (fastboot flash misc OKAY)"
      say "$(echo "$out" | grep -E 'Writing|OKAY' | tail -1)"
      exit 0
    fi
    say "attempt failed: $(echo "$out" | tail -1)"
  fi
  sleep 60
done
say "gave up after 6h - fastboot never appeared"
exit 1
