#!/usr/bin/env bash
# Catch the loader's SHORT window and run the probe -> reader sequence.
#
# The loader auto-boots the installed kernel within a few seconds of a reset,
# so a poll that reads the product file every 10 s misses it entirely (that is
# how the v281 probe flash failed). This polls `fastboot devices` every second
# and flashes the instant the serial appears.
cd /home/placeless/dev/p20-root || exit 1
LOG="logs/catch_lk_$(date +%H%M%S).log"
exec >>"$LOG" 2>&1
S=SCV7N18927000473

wait_lk() {
  for _ in $(seq 1 1800); do
    if fastboot devices 2>/dev/null | grep -q "$S"; then return 0; fi
    sleep 1
  done
  return 1
}

echo "=== armed, waiting for the loader $(date +%H:%M:%S)"
wait_lk || { echo "timeout waiting for LK"; exit 1; }
echo "=== LK hit $(date +%H:%M:%S) -> flashing PROBE"
fastboot -s "$S" flash kernel artifacts/fullerene-ane-v281-probe.img
fastboot -s "$S" reboot

echo "=== probe away, waiting for the loader again"
wait_lk || { echo "timeout waiting for LK (probe leg)"; exit 1; }
echo "=== LK hit $(date +%H:%M:%S) -> flashing READER"
fastboot -s "$S" flash kernel artifacts/fullerene-ane-v282-reader.img
fastboot -s "$S" reboot

for _ in $(seq 1 40); do
  sleep 5
  P=$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)
  echo "$(date +%H:%M:%S) [$P]"
  if [ "$P" = "ANE fastboot" ]; then
    ~/.hermes/bin/uv run --with pyusb --no-project python3 adb_cycle.py log rings_night/probe_trail.bin
    python3 -c "
import re
d=open('rings_night/probe_trail.bin','rb').read()
m=re.search(rb'SMK:([0-9A-Fa-f]+)', d)
print('TRAIL:', ''.join(chr(c) if 32<=c<127 else '.' for c in bytes.fromhex(m.group(1).decode())) if m else 'no SMK line')
"
    break
  fi
done
echo "=== done $(date +%H:%M:%S) product=[$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)]"
