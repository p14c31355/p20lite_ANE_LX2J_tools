#!/bin/bash
# Watch for the L2 responder's enumeration (12d1:0001) and record everything
# about it the moment it appears: kernel log lines and a full descriptor dump.
# The L2 probe's only successful observable is the host seeing this device, so
# this is the readout instrument for it.
cd /home/placeless/dev/p20-root || exit 1
OUT=usb_runs/l2_enum_$(date +%m%d_%H%M).log
echo "[$(date +%H:%M:%S)] watching for 12d1:0001 (L2 responder)" | tee "$OUT"
for i in $(seq 1 3600); do          # ~4h at 4s
  if lsusb -d 12d1:0001 >/dev/null 2>&1; then
    {
      echo "[$(date +%H:%M:%S)] ENUMERATED: $(lsusb -d 12d1:0001)"
      echo "--- dmesg (usb):"
      dmesg 2>/dev/null | tail -40 | grep -iE "usb|12d1|new .*device" | tail -20
      echo "--- lsusb -v:"
      lsusb -v -d 12d1:0001 2>/dev/null | head -60
    } | tee -a "$OUT"
    # keep recording for 90s in case the host finishes enumeration after us
    sleep 90
    dmesg 2>/dev/null | tail -60 | grep -iE "usb|12d1" | tail -25 | tee -a "$OUT"
    exit 0
  fi
  # also stop early if fastboot shows up again (the probe cycle already moved on)
  sleep 4
done
echo "[$(date +%H:%M:%S)] timeout, never saw 12d1:0001" | tee -a "$OUT"
