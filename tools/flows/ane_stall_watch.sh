#!/bin/bash
# Loud stall detector for the unattended loop: if the device fingerprint and
# the newest runner log have not moved for 25 minutes, record it (the log is
# the evidence trail for the morning) and take one shot at the rootless USB
# stimuli. The runner itself only acts on fastboot/adb states, so a device
# parked in something else is exactly the case this exists for.
set -u
cd "$(dirname "$0")"
# next occurrence of a wall-clock time, today or tomorrow (a naive
# "today 06:00" is in the past for every evening launch).
next_at() { local t n; t=$(date -d "today $1" +%s); n=$(date +%s); [ "$n" -ge "$t" ] && t=$(date -d "tomorrow $1" +%s); echo "$t"; }
DEADLINE=$(next_at 06:00)   # computed once: recomputing would slide past it
LAST=""
LASTMOVE=$(date +%s)
while :; do
  NOW=$(date +%s)
  [ "$NOW" -ge "$DEADLINE" ] && exit 0
  # Progress = a change in the device's USB fingerprint (identity + interface
  # count). The newest runner log was part of this once, but the runner's
  # status lines grow it every minute and masked exactly the stalls this
  # exists to catch (measured: 25 min stuck at 2 interfaces, never flagged).
  IFACES=$(lsusb -v -d 12d1:107e 2>/dev/null | grep -cE "bInterfaceNumber")
  FP="$(lsusb | grep -oE '12d1:107e|18d1:d00d' | head -1):${IFACES}"
  if [ "$FP" != "$LAST" ]; then LAST="$FP"; LASTMOVE=$NOW; fi
  if [ $((NOW - LASTMOVE)) -gt 1500 ]; then
    echo "[$(date +%H:%M:%S)] STALL: no state change or log growth for 25 min (fp=$FP)" >> usb_runs/stall_watch.log
    timeout 20 python3 tools/ane_usb_reset_user.py >> usb_runs/stall_watch.log 2>&1 || true
    LASTMOVE=$NOW
    sleep 1200
  fi
  sleep 60
done
