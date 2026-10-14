#!/usr/bin/env python3
"""v24 engine transform: night_engine_v23.sh -> night_engine_v24.sh

Remove the v22 marks fetch: it was conversation #2 in the window and raced
the magic reset (boot c6: 40 s, no OKAY). v214 now dumps the step-mark
trail into the ring as "SMK:..." every 256 beats, so the normal CNXN
collection carries it - no second conversation needed.
"""

src = open("night_engine_v23.sh").read()

old = '''        if [ "$CNXN_OK" = "1" ]; then
          # v22: fetch the v213 step markers while the boot is still alive
          # (plain-store trail at 0x348df000; a small read is EIO-safe).
          timeout 40 "$UV" run --with pyusb --no-project python3 fb_xfer.py r 348df000 40 "forensics/marks_c${c}.bin" >>"$LOG" 2>&1 || true
        fi
'''
assert old in src, "v22 marks block not found"
src = src.replace(old, "", 1)

src = src.replace("night engine v23 start", "night engine v24 start")
src = src.replace("night engine v23 done", "night engine v24 done")

open("night_engine_v24.sh", "w").write(src)
print("night_engine_v24.sh written,", len(src), "chars")
