#!/usr/bin/env python3
"""v23 engine transform: night_engine_v22.sh -> night_engine_v23.sh

The race is still lost: the sequence [attach -> up to 96 s product wait ->
45 s fixe settle -> CNXN] routinely exceeds the 80-180 s beat-cap
lifetime. The v192 law says the FIRST conversation per window is the
reliable one, so v23 polls for the clean state (product "ANE fastboot" or
the /sys descriptors at >= 50 bytes) and fires the CNXN ~9 s after the
state goes clean - total attach->CNXN in the 20-40 s range.
"""

src = open("night_engine_v22.sh").read()

import re
m = re.search(r"        # v22: settle 45 s.*?\n        for _s in \$\(seq 1 15\); do\n.*?\n        done\n", src, re.S)
assert m, "v22 settle block not found"
old = m.group(0)
new = '''        # v23: poll for the clean state (product "ANE fastboot" or the
        # /sys descriptors at >= 50 bytes), then ~9 s of grace to let the
        # string reads finish, then CNXN immediately. The launchd-era
        # boots die at the 16384-beat cap in 80-180 s real time, and the
        # v192 law says the FIRST conversation per window is the reliable
        # one - a fixed settle loses the race.
        _grace=0
        for _s in $(seq 1 20); do
          last_p="$(journalctl -k -n 40 --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
          case "$last_p" in
            *"Fastboot2.0"*) break ;;
          esac
          _dsz=$(wc -c < /sys/bus/usb/devices/1-1/descriptors 2>/dev/null || echo 0)
          if printf '%s' "$last_p" | grep -q "ANE fastboot" || [ "$_dsz" -ge 50 ]; then
            _grace=$((_grace+1))
            [ "$_grace" -ge 3 ] && break
          else
            _grace=0
          fi
          sleep 3
        done
'''
src = src.replace(old, new, 1)

# 2. early exit in the product wait when the descriptors are already clean
old_wait = '''      for _w in $(seq 1 30); do
        sleep 3
        last_p="$(journalctl -k --since "@${_w0}" --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
        [ -n "$last_p" ] && break
      done'''
new_wait = '''      for _w in $(seq 1 30); do
        sleep 3
        last_p="$(journalctl -k --since "@${_w0}" --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
        [ -n "$last_p" ] && break
        # v23: a 50-byte descriptor set is a collectable boot even while
        # the string reads stall - do not burn the whole wait on it.
        _dsz=$(wc -c < /sys/bus/usb/devices/1-1/descriptors 2>/dev/null || echo 0)
        [ "$_dsz" -ge 50 ] && break
      done'''
assert old_wait in src, "product wait block not found"
src = src.replace(old_wait, new_wait, 1)

src = src.replace("night engine v22 start", "night engine v23 start")
src = src.replace("night engine v22 done", "night engine v23 done")

open("night_engine_v23.sh", "w").write(src)
print("night_engine_v23.sh written,", len(src), "chars")
