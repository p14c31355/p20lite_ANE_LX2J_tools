#!/usr/bin/env bash
# v283 unattended probe: catch the short loader window, flash the bounded-wait
# probe, and let it run LONG (no reader flash) to see whether the boot now
# reaches the desktop instead of parking in the predesktop-config wait.
# Evidence: the WD: lines and the trail in the next collection, plus whether
# the loader round-trip stops happening (a parked boot self-heals in ~100 s).
cd /home/placeless/dev/p20-root || exit 1
LOG="logs/v283_run_$(date +%H%M%S).log"
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
echo "=== LK $(date +%H:%M:%S) -> v283 probe"
fastboot -s "$S" flash kernel artifacts/fullerene-ane-v283-boundedwait.img
fastboot -s "$S" reboot

# Watch the product string for 20 minutes. A parked boot would reset itself to
# the loader within ~100 s (watchdog); surviving 20 min means the wait is gone.
for i in $(seq 1 240); do
  sleep 5
  P=$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)
  [ $((i % 12)) -eq 0 ] && echo "$(date +%H:%M:%S) [$P]"
  if [ "$P" = "Fastboot2.0" ]; then
    echo "=== RESET to loader at $(date +%H:%M:%S) - boot did NOT survive (watchdog path again)"
    exit 2
  fi
  if [ "$P" = "ANE fastboot" ]; then
    # Still alive at this check; keep watching but also try a collection.
    if [ "$COLLECTED" != "1" ] && [ "$i" -gt 36 ]; then
      COLLECTED=1
      echo "=== collecting after 3 min alive $(date +%H:%M:%S)"
      ~/.hermes/bin/uv run --with pyusb --no-project python3 adb_cycle.py log rings_night/v283_alive.bin
      python3 -c "
import re
d=open('rings_night/v283_alive.bin','rb').read()
m=re.search(rb'SMK:([0-9A-Fa-f]+)', d)
print('TRAIL:', ''.join(chr(c) if 32<=c<127 else '.' for c in bytes.fromhex(m.group(1).decode())) if m else 'no SMK line')
" 2>/dev/null
      for s in $(strings rings_night/v283_alive.bin | grep -aE "WD:|timeout|predesktop" | head -6); do echo "RING: $s"; done
    fi
  fi
done
echo "=== survived 20 min $(date +%H:%M:%S) product=[$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)]"
