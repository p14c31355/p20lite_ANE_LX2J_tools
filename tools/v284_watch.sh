#!/usr/bin/env bash
# v284 watchdog-watch: catch the loader, flash the safe-arming build, then
# watch 25 min. Three outcomes are distinguishable:
#   exit 2  = reset to loader again (v283's path: enumeration watchdog)
#   exit 0  = survived 25 min (arming was the killer - the v283 result stands)
#   collected trail + RING lines printed for the surviving boot
cd /home/placeless/dev/p20-root || exit 1
LOG="logs/v284_run_$(date +%H%M%S).log"
exec >>"$LOG" 2>&1
S=SCV7N18927000473

wait_lk() {
  for _ in $(seq 1 1800); do
    if fastboot devices 2>/dev/null | grep -q "$S"; then return 0; fi
    sleep 1
  done
  return 1
}

echo "=== armed $(date +%H:%M:%S)"
wait_lk || { echo "timeout"; exit 1; }
echo "=== LK $(date +%H:%M:%S) -> v284 safe-arming probe"
fastboot -s "$S" flash kernel artifacts/fullerene-ane-v284-safearm.img
fastboot -s "$S" reboot

for i in $(seq 1 300); do
  sleep 5
  P=$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)
  [ $((i % 12)) -eq 0 ] && echo "$(date +%H:%M:%S) [$P]"
  if [ "$P" = "Fastboot2.0" ]; then
    echo "=== RESET to loader at $(date +%H:%M:%S) - still dying (v283 path confirmed)"
    exit 2
  fi
  if [ "$P" = "ANE fastboot" ] && [ "$i" -gt 36 ] && [ "$COLLECTED" != "1" ]; then
    COLLECTED=1
    echo "=== collecting after 3 min alive $(date +%H:%M:%S)"
    ~/.hermes/bin/uv run --with pyusb --no-project python3 adb_cycle.py log rings_night/v284_alive.bin
    python3 -c "
import re
d=open('rings_night/v284_alive.bin','rb').read()
m=re.search(rb'SMK:([0-9A-Fa-f]+)', d)
print('TRAIL:', ''.join(chr(c) if 32<=c<127 else '.' for c in bytes.fromhex(m.group(1).decode())) if m else 'no SMK line')
" 2>/dev/null
    strings rings_night/v284_alive.bin | grep -aE "WD:|timeout|predesktop|IQ:" | head -8
  fi
done
echo "=== survived 25 min $(date +%H:%M:%S)"
