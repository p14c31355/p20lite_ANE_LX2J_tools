#!/bin/bash
# Rescue-revive watcher: pull the device out of the eRecovery unattended.
#
# The eRecovery (12d1:107e, one Mass Storage interface, no adb/fastboot) has no
# host interface of its own, but it re-enumerates its gadget periodically -
# evidence of a state machine that reacts to the USB link. This watcher tests
# the hypothesis that a logical unplug/replug drives it out:
#
#   - on every rescue sighting it runs the root helper once
#     (tools/ane_usb_revive_root.sh, the authorized 0/1 dance),
#   - escalating the hold time, with growing waits between attempts,
#   - logging every state transition it sees, forever.
#
# It deliberately does NOT touch fastboot or adb states: the run script's own
# tail restores the stock kernel there, and two actors flashing at once is the
# one thing this project must never do.
#
# Needs one one-time setup for the root helper (see the message that shipped
# with this file):
#   placeless ALL=(root) NOPASSWD: /home/placeless/dev/p20-root/tools/ane_usb_revive_root.sh
# Without it the watcher still runs and logs; the revive attempts report
# "no passwordless sudo" and are skipped.
set -u
cd "$(dirname "$0")"
LOG=usb_runs/revive_$(date +%Y%m%d_%H%M%S).log
mkdir -p usb_runs

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

state() {
  if timeout 6 fastboot devices 2>/dev/null | grep -q . ; then echo fastboot; return; fi
  if timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$"; then echo adb; return; fi
  if lsusb 2>/dev/null | grep -q "12d1:107e"; then
    # one interface = rescue, six = android mid-boot
    n=$(lsusb -v -d 12d1:107e 2>/dev/null | grep -cE "bInterfaceNumber")
    if [ "$n" -le 1 ]; then echo rescue; else echo android-usb; fi
    return
  fi
  echo dark
}

say "watcher started (log: $LOG)"
last=""
attempt=0
holds=(6 20 2 45 6 20)
waits=(60 120 30 300 120 240)
while true; do
  s=$(state)
  if [ "$s" != "$last" ]; then
    say "state: $s"
    last="$s"
  fi
  case "$s" in
    fastboot|adb)
      say "device reachable ($s) - the run tail owns it from here; watcher stays passive"
      attempt=0
      ;;
    rescue)
      if sudo -n true 2>/dev/null; then
        h=${holds[$((attempt % ${#holds[@]}))]}
        say "rescue: revive attempt $((attempt + 1)) (hold ${h}s)"
        if sudo -n /home/placeless/dev/p20-root/tools/ane_usb_revive_root.sh "$h" 2>&1 | tee -a "$LOG" | grep -q "replugged"; then
          w=${waits[$((attempt % ${#waits[@]}))]}
          say "replugged; waiting ${w}s to see what the rescue does"
          attempt=$((attempt + 1))
          sleep "$w"
          continue
        fi
      else
        say "rescue present but no passwordless sudo for the helper (passive only)"
      fi
      sleep 30
      ;;
    *)
      sleep 15
      ;;
  esac
  sleep 10
done
