#!/bin/bash
# ring_watch.sh: exit (and notify) as soon as a non-empty ring lands in
# rings_night/. The engine keeps cycling meanwhile.
set -u
cd ~/dev/p20-root
while true; do
  for f in rings_night/adb_c*.bin; do
    [ -f "$f" ] || continue
    sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
    if [ "$sz" -gt 0 ]; then
      echo "RING LANDED: $f ($sz bytes) at $(date +%H:%M:%S)"
      exit 0
    fi
  done
  sleep 10
done
