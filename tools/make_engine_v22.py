#!/usr/bin/env python3
"""v22 engine transform: night_engine_v21.sh -> night_engine_v22.sh

The launchd-era boots now die at the 16384-beat cap in 80-180 s real time.
The 75 s settle (25 x 3 s) + CNXN often lost the race (boot #35: clean
attach +28 s, death +80 s, collection attempt lost). v22: settle 45 s
(15 x 3 s), and after a successful collection fetch the v213 step markers
(0x348df000, 64 B) while the boot is still alive.
"""

src = open("night_engine_v21.sh").read()

old_settle = "        for _s in $(seq 1 25); do"
new_settle = "        # v22: settle 45 s (15 x 3 s) - the launchd-era boots die at\n        # the 16384-beat cap in 80-180 s real time; 75 s lost the race.\n        for _s in $(seq 1 15); do"
assert old_settle in src, "settle loop not found"
src = src.replace(old_settle, new_settle, 1)

anchor = "        # v183: two ring-xfer attempts per boot."
assert anchor in src, "v183 anchor not found"
marks = '''        if [ "$CNXN_OK" = "1" ]; then
          # v22: fetch the v213 step markers while the boot is still alive
          # (plain-store trail at 0x348df000; a small read is EIO-safe).
          timeout 40 "$UV" run --with pyusb --no-project python3 fb_xfer.py r 348df000 40 "forensics/marks_c${c}.bin" >>"$LOG" 2>&1 || true
        fi
'''
src = src.replace(anchor, marks + anchor, 1)

src = src.replace("night engine v21 start", "night engine v22 start")
src = src.replace("night engine v21 done", "night engine v22 done")

open("night_engine_v22.sh", "w").write(src)
print("night_engine_v22.sh written,", len(src), "chars")
