#!/usr/bin/env bash
# v285 decisive unattended-boot experiment: production path (desktop on) +
# bounded predesktop wait (5 s) + enumeration watchdog disarmed with the
# closed pump window + pump window closed after handoff.
# Expected: the unattended boot reaches the desktop/launchd instead of the
# enumeration watchdog's ~100 s reset.
cd /home/placeless/dev/p20-root || exit 1
LOG="logs/v285_run_$(date +%H%M%S).log"
exec >>"$LOG" 2>&1
S=SCV7N18927000473

wait_lk() {
  for _ in $(seq 1 2400); do
    if fastboot devices 2>/dev/null | grep -q "$S"; then return 0; fi
    sleep 1
  done
  return 1
}

echo "=== armed $(date +%H:%M:%S)"
wait_lk || { echo "timeout"; exit 1; }
echo "=== LK $(date +%H:%M:%S) -> flashing v285"
fastboot -s "$S" flash kernel artifacts/fullerene-ane-v285-wdwindow.img
sleep 2
fastboot -s "$S" reboot

# Watch 25 min. The enumeration watchdog should be disarmed with the closed
# window, so a watchdog reset here means the flag did not propagate.
survived_min=0
for i in $(seq 1 300); do
  sleep 5
  P=$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)
  [ $((i % 12)) -eq 0 ] && echo "$(date +%H:%M:%S) [$P]"
  if [ "$P" = "Fastboot2.0" ]; then
    echo "=== RESET to loader at $(date +%H:%M:%S) - watchdog still fires"
    exit 2
  fi
done
echo "=== final $(date +%H:%M:%S) product=[$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)]"
