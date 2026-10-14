#!/bin/bash
# One-shot digest of a night's run: probe activity, USB evidence, the
# USB-default flow, and the watchers' logs, in the order the morning wants
# them. Read-only; nothing here touches the phone.
cd "$(dirname "$0")" || exit 1
RUN=${1:-$(ls -t usb_runs/night_*.log 2>/dev/null | grep -v journal | head -1)}
[ -n "$RUN" ] || { echo "no night log found"; exit 1; }
JLOG="usb_runs/night_journal_${RUN##*night_}"
echo "############ night digest ############"
echo "runner log : $RUN"
echo "journal    : $JLOG"
echo
echo "== runner start/stop"
grep -E "night runner start|exiting|wind-down" "$RUN" | head -4
echo
echo "== probes fired (in order)"
grep -E "PROBE: artifacts" "$RUN" | head -40
echo
echo "== state transitions"
grep -E "^\[[0-9:]*\] state:" "$RUN" | tail -40
echo
echo "== RESTORE / USBJOB lines"
grep -E "RESTORE|USBJOB" "$RUN" | tail -20
echo
echo "== USB attach evidence (host kernel, journal sweep)"
grep -E "new (high|full|low)-speed|New USB device|error -|usb 1-1" "$JLOG" 2>/dev/null | tail -30
echo
echo "== klog capture: USB lines (buffered; may lag)"
grep -E "usb 1-1|new (high|full|low)-speed" usb_runs/klog_*.log 2>/dev/null | tail -30
echo
echo "== USB-default flow"
tail -25 usb_runs/usb_default_flow.log 2>/dev/null
if [ -f .usb_default_done ]; then echo "marker: .usb_default_done PRESENT (persist set to mtp,adb)"; fi
echo
echo "== refill / stall / screen logs"
tail -5 usb_runs/loop_refill.log 2>/dev/null
tail -5 usb_runs/stall_watch.log 2>/dev/null
tail -5 usb_runs/screen_watch.log 2>/dev/null
echo
echo "== camera captures by probe"
for d in usb_runs/cam_*/; do
  n=$(ls "$d" 2>/dev/null | grep -c jpg)
  echo "  $d: $n frames"
done
echo
echo "== step-mark readout helper: newest probe frames"
for d in $(ls -td usb_runs/cam_*/ 2>/dev/null | head -2); do
  echo "  $d"
  ls -t "$d" | head -4 | sed 's/^/    /'
done
