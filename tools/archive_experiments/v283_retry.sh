#!/usr/bin/env bash
cd /home/placeless/dev/p20-root || exit 1
S=SCV7N18927000473
for _ in $(seq 1 2400); do
  if fastboot devices 2>/dev/null | grep -q "$S"; then
    sleep 2
    echo "=== LK $(date +%H:%M:%S) -> v283"
    fastboot -s "$S" flash kernel artifacts/fullerene-ane-v283-boundedwait.img
    sleep 2
    fastboot -s "$S" reboot
    break
  fi
  sleep 1
done
for i in $(seq 1 30); do
  sleep 10
  P=$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)
  echo "$(date +%H:%M:%S) [$P]"
  if [ "$P" = "ANE fastboot" ]; then
    sleep 60
    echo "=== alive check: [$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)]"
    ~/.hermes/bin/uv run --with pyusb --no-project python3 adb_cycle.py log rings_night/v283_c1.bin
    break
  fi
done
echo "=== done $(date +%H:%M:%S)"
