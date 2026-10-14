#!/bin/bash
# Fire ONE non-magic piggyback at exactly N seconds after the next clean
# ANE-fastboot attach. Usage: timed_piggy.sh <delay_s>
set +m
cd ~/dev/p20-root
DELAY="${1:-75}"
BASE=$(journalctl -k --no-pager | grep -c 'Product: ANE fastboot')
echo "baseline=$BASE waiting for attach..."
for i in $(seq 1 150); do
  N=$(journalctl -k --no-pager | grep -c 'Product: ANE fastboot')
  [ "$N" -gt "$BASE" ] && { echo "attach at $(date +%H:%M:%S)"; break; }
  sleep 0.5
done
sleep "$DELAY"
/home/placeless/.hermes/bin/uv run --with pyusb --no-project python3 piggy_series.py 3 "rings_night/d${DELAY}" 2>&1 | tail -4
