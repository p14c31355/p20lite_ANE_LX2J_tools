#!/usr/bin/env bash
# v266 additive USB-SPI probe loop (corrected classifier).
#
# CRITICAL: the loader and the kernel expose the SAME VID:PID:serial
# (18d1:d00d / SCV7N18927000473), so `fastboot devices` matches both. Classify
# by the sysfs product string instead: "Fastboot2.0" = loader (flash),
# "ANE fastboot" = kernel (collect). A missing/[[garbled]] product = wait.
set -u
P20=/home/placeless/dev/p20-root
S=SCV7N18927000473
IMG="$P20/artifacts/fullerene-ane-v266-usbspi-probe.img"
LOG="$P20/logs/v266_loop_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$P20/rings_night"
exec >>"$LOG" 2>&1
say() { echo "[$(date '+%m%d %H:%M:%S')] $*"; }
say "loop start img=$IMG"
cycle=0
while [ "$cycle" -lt 80 ]; do
  cycle=$((cycle+1))
  dev=$(ls -d /sys/bus/usb/devices/1-1 2>/dev/null)
  if [ -z "$dev" ]; then say "cycle $cycle: no device"; sleep 8; continue; fi
  prod=$(cat "$dev/product" 2>/dev/null || echo "")
  case "$prod" in
    "Fastboot2.0")
      say "cycle $cycle: LOADER -> flash"
      timeout 60 fastboot -s "$S" flash kernel "$IMG" 2>&1 | tail -1
      timeout 30 fastboot -s "$S" reboot 2>&1 | tail -1
      sleep 40
      ;;
    "ANE fastboot")
      out="$P20/rings_night/v266_$(date +%m%d_%H%M%S).bin"
      say "cycle $cycle: KERNEL -> collect"
      timeout 90 "$HOME/.hermes/bin/uv" run --with pyusb --no-project python3 \
        "$P20/adb_cycle.py" log "$out" 2>&1 | tail -2
      if [ -s "$out" ]; then
        say "  ring $(wc -c < "$out") B; markers:"
        strings "$out" | grep -aE "USBDWC2|UD8|IQ:|SMK" | head -6
      fi
      sleep 15
      ;;
    *)
      say "cycle $cycle: product='${prod}' (garbled/absent) -> wait"
      sleep 15
      ;;
  esac
done
say "loop end after $cycle cycles"
