#!/bin/bash
# Wait for the NEXT "restored stock kernel" line in the catcher log (the
# RESTORE fire of the [key-probe, pmsg-dump, RESTORE] queue), then run the
# pstore readout: Android -> root -> pull pmsg.bin/console.bin.
set -u
cd "$(dirname "$0")"
LOG=usb_runs/fast_catcher.log
BEFORE=$(grep -c "restored stock kernel" "$LOG" 2>/dev/null || echo 0)
echo "$(date '+%H:%M:%S') waiting for a NEW restore fire (currently $BEFORE)"
for i in $(seq 1 720); do
  NOW=$(grep -c "restored stock kernel" "$LOG" 2>/dev/null || echo 0)
  if [ "$NOW" != "$BEFORE" ]; then
    echo "$(date '+%H:%M:%S') new restore fire seen; starting the readout"
    exec bash ane_pmsg_read.sh
  fi
  sleep 5
done
echo "$(date '+%H:%M:%S') no new restore fire within an hour"
exit 1
