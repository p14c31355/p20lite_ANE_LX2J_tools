#!/bin/bash
# Watch for the ANE-LX2J after a failed boot: the fastboot window (18d1:d00d,
# serial shown by `fastboot devices`) or the loader's eRecovery fallback
# (12d1:107e with a single interface). One detection, then exit.
SERIAL=SCV7N18927000473
while true; do
  ts=$(date '+%H:%M:%S')
  if timeout 5 fastboot devices 2>/dev/null | grep -q "$SERIAL"; then
    echo "FASTBOOT_READY $ts"
    exit 0
  fi
  if lsusb -d 12d1:107e >/dev/null 2>&1; then
    n=$(lsusb -v -d 12d1:107e 2>/dev/null | grep -c "bInterfaceClass")
    if [ "$n" -le 1 ]; then
      echo "ERECOVERY_FALLBACK $ts (iface=$n) - combo needed"
      exit 2
    fi
  fi
  sleep 2
done
