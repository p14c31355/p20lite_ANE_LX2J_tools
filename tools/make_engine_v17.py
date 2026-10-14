#!/usr/bin/env python3
"""v17 engine transform: night_engine_v16.sh -> night_engine_v17.sh

The classification ran ~2 s after the attach event, but the product line
only prints when the enumeration COMPLETES (which takes seconds when the
host's retries are in play). Boot #22's clean attach (dev 63) was
classified "product-less; skip" at +2 s and the whole boot was missed.
v17: on an empty product, wait (bounded, 14 x 3 s) for THIS attach's
product line before deciding.
"""
import sys

src = open("night_engine_v16.sh").read()

src = src.replace(
    'log "=== night engine v16 start img=$IMG cycles=$CYCLES ==="',
    'log "=== night engine v17 start img=$IMG cycles=$CYCLES ==="')
src = src.replace('log "=== night engine v16 done ==="',
                  'log "=== night engine v17 done ==="')

old = '''    if [ -z "$last_p" ]; then
      log "c$c: product-less attach; skip (no sessions possible)"
      continue
    fi'''
new = '''    if [ -z "$last_p" ]; then
      # v17: the product line prints when the enumeration COMPLETES, which
      # can take seconds (host retries). Wait (bounded) for THIS attach's
      # product before deciding - a clean attach must not be skipped in
      # its first 2 s (boot #22 was).
      log "c$c: attach in flight; waiting for product"
      for _w in $(seq 1 14); do
        sleep 3
        last_p="$(journalctl -k -n 300 --no-pager 2>/dev/null | grep -A8 "usb 1-1: new high-speed USB device number ${DEVNO} " | grep "usb 1-1: Product: " | head -1)"
        [ -n "$last_p" ] && break
      done
      if [ -z "$last_p" ]; then
        log "c$c: product-less attach; skip (no sessions possible)"
        continue
      fi
      log "c$c: product arrived late: $last_p"
    fi'''
if old not in src:
    sys.exit("product-less block anchor missing")
src = src.replace(old, new)

open("night_engine_v17.sh", "w").write(src)
print("night_engine_v17.sh written:", len(src), "bytes")
