#!/bin/bash
# Auto-run the USB-default flow the moment adb appears: the fixed
# ane_set_usb_default.sh carries the proven recipe (fresh+settled boot, the
# frozen exploit by md5, fifo root shell). On success: mark done, record, and
# put the waiting probe queue back so the night runner resumes the cycle from
# the next adb window ("reboot to bootloader for the next probe").
#
# Notes on the failure mode seen at 21:22: a failed exploit run leaves the
# boot wedged (MTP-only, no adb), so a retry is only possible after the next
# fresh boot - the loop naturally waits for adb to come back, and spaces runs
# out to avoid hammering a wedged boot.
set -u
cd "$(dirname "$0")"
[ -f .usb_default_done ] && { echo "usb default already done - nothing to watch"; exit 0; }
RUNS=0
while [ "$RUNS" -lt 40 ]; do
  if timeout 15 adb devices 2>/dev/null | awk 'NR==2{print $2}' | grep -q device; then
    RUNS=$((RUNS + 1))
    echo "== [$(date +%H:%M:%S)] adb up (run $RUNS): USB-default flow"
    if ! timeout 15 adb shell getprop 2>/dev/null | grep -q .; then
      echo "  adb is there but shell is not; waiting"
      sleep 30
      continue
    fi
    if timeout 1800 bash ane_set_usb_default.sh >> usb_runs/usb_default_flow.log 2>&1; then
      if timeout 10 adb shell getprop persist.sys.usb.config 2>/dev/null | tr -d '\r' | grep -q "mtp,adb"; then
        touch .usb_default_done
        echo "== [$(date +%H:%M:%S)] SUCCESS: persist.sys.usb.config = mtp,adb"
        {
          echo "# $(date '+%F %T') USB default set to mtp,adb (persist)"
          echo "flow log: usb_runs/usb_default_flow.log"
          echo "uproot: ane_set_usb_default.sh (frozen exploit 0x134c838, fresh+settled boot)"
        } >> docs/ANE_NIGHT_20261002.md
        if [ -s night_queue.probes.pending ]; then
          cp night_queue.probes.pending night_queue.txt
          echo "== probe queue restored ($(wc -l < night_queue.txt) entries)"
        fi
        exit 0
      fi
    fi
    echo "  flow did not confirm; tail of the log:"
    tail -6 usb_runs/usb_default_flow.log 2>/dev/null
    sleep 420      # a failed run may have wedged/slowed the boot; wait for the next one
  fi
  sleep 15
done
echo "== [$(date +%H:%M:%S)] gave up after $RUNS runs"
touch .usb_flow_gaveup
