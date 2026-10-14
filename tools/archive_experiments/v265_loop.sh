#!/usr/bin/env bash
# v264 event-driven (DWC2 SPI 159) overnight loop.
# Detects the LK loader window, flashes the v264 image, then collects the ring
# through the CNXN piggyback. Records every attempt so the morning read has the
# full distribution (garbled / clean / collector outcome).
set -u
P20=/home/placeless/dev/p20-root
S=SCV7N18927000473
IMG="$P20/artifacts/fullerene-ane-v265-usbspi-gint.img"
LOG="$P20/logs/v265_loop_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$P20/rings_night"
exec >>"$LOG" 2>&1

say() { echo "[$(date '+%m%d %H:%M:%S')] $*"; }

say "loop start img=$IMG"

flash_and_reboot() {
  timeout 60 fastboot -s "$S" flash kernel "$IMG" 2>&1 | tail -2
  timeout 30 fastboot -s "$S" reboot 2>&1 | tail -1
}

cycle=0
while [ "$cycle" -lt 40 ]; do
  cycle=$((cycle+1))
  # 1) Loader window: flash immediately.
  if timeout 8 fastboot devices 2>/dev/null | grep -q "$S"; then
    say "cycle $cycle: LK window -> flash"
    flash_and_reboot
    sleep 45
    continue
  fi
  # 2) Kernel present? Classify by product string.
  prod=$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null || echo "")
  case "$prod" in
    "ANE fastboot")
      out="$P20/rings_night/v264_$(date +%m%d_%H%M%S).bin"
      say "cycle $cycle: kernel up -> collect"
      timeout 90 "$HOME/.hermes/bin/uv" run --with pyusb --no-project python3 \
        "$P20/adb_cycle.py" log "$out" 2>&1 | tail -3
      if [ -s "$out" ]; then
        say "  ring bytes: $(wc -c < "$out")"
        strings "$out" | grep -aE "UD8|IQ:|SMK|W=" | head -6
      fi
      ;;
    *) : ;;  # garbled / absent: wait
  esac
  sleep 8
done
say "loop end after $cycle cycles"
