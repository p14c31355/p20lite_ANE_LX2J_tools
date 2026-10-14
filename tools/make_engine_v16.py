#!/usr/bin/env python3
"""v16 engine transform: night_engine_v15.sh -> night_engine_v16.sh

v15's classifier still used `grep "Product: " | tail -1` over ALL recent
lines. A product-less kernel attach (dev 53, 17:26, "SerialNumber:
Fullerene" only) classified as "loader attach" because the tail product
line was the older LK's. v16 scopes the product search to the CURRENT
attach's device number: only lines within -A8 of that attach.
"""
import sys

src = open("night_engine_v15.sh").read()

src = src.replace(
    'log "=== night engine v15 start img=$IMG cycles=$CYCLES ==="',
    'log "=== night engine v16 start img=$IMG cycles=$CYCLES ==="')
src = src.replace('log "=== night engine v15 done ==="',
                  'log "=== night engine v16 done ==="')

old = '''    # v15: CUR is the attach line; classify via the product line.
    last_p="$(journalctl -k -n 600 --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"'''
new = '''    # v15: CUR is the attach line; classify via the product line.
    # v16: SCOPE the product search to THIS attach's device number - the
    # unscoped tail-1 grabbed the PREVIOUS attach's product line and
    # mislabelled product-less kernel attaches as "loader" (dev 53).
    DEVNO="$(printf '%s' "$CUR" | sed -n 's/.*device number \\([0-9]*\\).*/\\1/p')"
    last_p="$(journalctl -k -n 300 --no-pager 2>/dev/null | grep -A8 "usb 1-1: new high-speed USB device number ${DEVNO} " | grep "usb 1-1: Product: " | head -1)"'''
if old not in src:
    sys.exit("classifier anchor missing")
src = src.replace(old, new)

open("night_engine_v16.sh", "w").write(src)
print("night_engine_v16.sh written:", len(src), "bytes")
