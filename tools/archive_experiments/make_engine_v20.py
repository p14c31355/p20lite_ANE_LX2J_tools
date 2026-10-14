#!/usr/bin/env python3
"""v20 engine transform: night_engine_v19.sh -> night_engine_v20.sh

The v18 product-wait anchored its `--since` at (now - 8 s). That is right
only when the wait starts within a couple of seconds of the attach - on
the v19 restart path the gap was ~33 s, so the product line (attach + 6 s)
fell OUTSIDE the window and a CLEAN boot (dev 75) was declared
product-less. v20 anchors the window at the ATTACH's own epoch (parsed
from the journal with -o short-unix), minus 2 s of slack.
"""

src = open("night_engine_v19.sh").read()

old = '''      _w0=$(( $(date +%s) - 8 ))'''
new = '''      _w0=$(journalctl -k -o short-unix --no-pager 2>/dev/null | grep "usb 1-1: new high-speed USB device number ${DEVNO} " | tail -1 | awk '{print $1}' | cut -d. -f1)
      [ -z "$_w0" ] && _w0=$(( $(date +%s) - 8 ))
      _w0=$(( _w0 - 2 ))'''
assert old in src, "_w0 line not found"
src = src.replace(old, new, 1)

old_c = '''      # v18: --since anchored search instead of grep -A8 (the product line
      # can sit >8 lines below the attach line after error bursts).'''
new_c = '''      # v18: --since anchored search instead of grep -A8 (the product line
      # can sit >8 lines below the attach line after error bursts).
      # v20: the --since anchor is the ATTACH's epoch (journal -o
      # short-unix), not now-8s - on a restart the gap can exceed the
      # window and hide a perfectly good product line (boot #27).'''
assert old_c in src, "v18 comment not found"
src = src.replace(old_c, new_c, 1)
src = src.replace("night engine v19 start", "night engine v20 start")
src = src.replace("night engine v19 done", "night engine v20 done")

open("night_engine_v20.sh", "w").write(src)
print("night_engine_v20.sh written,", len(src), "chars")
