#!/usr/bin/env python3
"""v18 engine transform: night_engine_v17.sh -> night_engine_v18.sh

Two fixes over v17:
1. The product wait lengthens to ~90 s (30 x 3 s). Boot #26's garbled
   attach printed its product line later than the old 42 s window.
2. The product search is --since based (an epoch anchored 8 s before the
   wait started) instead of the `grep -A8` context window, which missed
   product lines printed >8 lines below the attach line (the -110/config
   error bursts push them down).
"""

src = open("night_engine_v17.sh").read()

old_block = '''      log "c$c: attach in flight; waiting for product"
      for _w in $(seq 1 14); do
        sleep 3
        last_p="$(journalctl -k -n 300 --no-pager 2>/dev/null | grep -A8 "usb 1-1: new high-speed USB device number ${DEVNO} " | grep "usb 1-1: Product: " | head -1)"
        [ -n "$last_p" ] && break
      done
'''
new_block = '''      log "c$c: attach in flight; waiting for product"
      _w0=$(( $(date +%s) - 8 ))
      for _w in $(seq 1 30); do
        sleep 3
        last_p="$(journalctl -k --since "@${_w0}" --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
        [ -n "$last_p" ] && break
      done
'''
assert old_block in src, "v17 wait block not found"
src = src.replace(old_block, new_block)

old_c = """      # v17: the product line prints when the enumeration COMPLETES, which
      # can take seconds (host retries). Wait (bounded) for THIS attach's
      # product before deciding - a clean attach must not be skipped in
      # its first 2 s (boot #22 was)."""
new_c = """      # v17/v18: the product line prints when the enumeration COMPLETES,
      # which can take many seconds (host retries + the -110 dance). Wait
      # (bounded, 90 s) for THIS attach's product before deciding - a
      # clean attach must not be skipped in its first 2 s (boot #22 was).
      # v18: --since anchored search instead of grep -A8 (the product line
      # can sit >8 lines below the attach line after error bursts)."""
assert old_c in src, "v17 comment not found"
src = src.replace(old_c, new_c)

src = src.replace("night engine v17 start", "night engine v18 start")
src = src.replace("night engine v17 done", "night engine v18 done")

open("night_engine_v18.sh", "w").write(src)
print("night_engine_v18.sh written,", len(src), "chars")
