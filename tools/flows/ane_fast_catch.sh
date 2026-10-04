#!/bin/bash
# Fast catcher: act within a second when the loader's fastboot appears.
#
# Measured today: the loader's post-failure fastboot window can be ~1.6 s
# (09:42:46-48) - too short for any 5-10 s poll. The kernel log announces the
# attach instantly (idVendor=18d1), so this script streams the journal and
# fires the moment it sees that line.
#
# On a catch it flashes the stock kernel and waits for Android. One catch per
# run; re-arm as needed. If the fastboot is already up when started, it acts
# immediately too.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473

say() { echo "[$(date +%H:%M:%S)] $*"; }

restore() {
  say "fastboot is up -> restoring the stock kernel"
  timeout 120 fastboot -s "$S" flash kernel firmware/kernel_stock.bin 2>&1 | tail -2
  timeout 60 fastboot -s "$S" reboot 2>&1 | head -1
  say "waiting for Android"
  for i in $(seq 1 120); do
    timeout 6 adb devices 2>/dev/null | grep -qP "^$S\s+device$" && { say "android is back"; return 0; }
    sleep 5
  done
  say "android did not appear (yet)"
  return 1
}

if timeout 6 fastboot devices 2>/dev/null | grep -q "^$S" ; then
  restore
  exit $?
fi

say "streaming the kernel log for the fastboot signature (idVendor=18d1)"
while IFS= read -r line; do
  case "$line" in
    *"idVendor=18d1"*)
      sleep 1
      if timeout 6 fastboot devices 2>/dev/null | grep -q "^$S" ; then
        restore
        exit 0
      fi
      ;;
  esac
done < <(timeout 3600 journalctl -k -f -n 0 2>/dev/null)
say "window closed without a catch"
exit 2
