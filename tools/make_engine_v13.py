#!/usr/bin/env python3
"""v13 engine transform: night_engine_v12.sh -> night_engine_v13.sh

1. version strings v12 -> v13
2. CNXN_OK flag on the collection loop
3. after a successful CNXN, SKIP the ring-xfer attempts (the magic reset
   lands within ~2-50 s; the xfers only timed out against the loader and
   wasted ~3 min per cycle). One 60 s xfer attempt remains for the
   failed-CNXN case.
4. run boot_ledger.py after each cycle's collection phase.
"""
import sys

src = open("night_engine_v12.sh").read()

reps = [
    ('log "=== night engine v12 start img=$IMG cycles=$CYCLES ==="',
     'log "=== night engine v13 start img=$IMG cycles=$CYCLES ==="'),
    ('log "=== night engine v12 done ==="',
     'log "=== night engine v13 done ==="'),
    ('        for a in 1 2 3; do\n          rm -f /tmp/adb_raw_last.bin',
     '        CNXN_OK=0\n        for a in 1 2 3; do\n          rm -f /tmp/adb_raw_last.bin'),
    ('            log "c$c: ring $(stat -c %s "rings_night/adb_${c}.bin" 2>/dev/null) bytes (attempt $a)"\n            break',
     '            log "c$c: ring $(stat -c %s "rings_night/adb_${c}.bin" 2>/dev/null) bytes (attempt $a)"\n            CNXN_OK=1\n            break'),
]

old_xfer = '''        for xa in 1 2; do
          rm -f "rings_night/ring_c${c}.bin"
          if timeout 90 "$UV" run --with pyusb --no-project python3 fb_xfer.py r 348d0000 8000 "rings_night/ring_c${c}.bin" >>"$LOG" 2>&1; then
            log "c$c: ring xfer $(stat -c %s "rings_night/ring_c${c}.bin" 2>/dev/null) bytes (attempt $xa)"
            break
          fi
          log "c$c: ring xfer attempt $xa failed"
          [ "$xa" = 1 ] && sleep 30
        done'''

new_xfer = '''        # v13: ring-xfer only as a fallback. When the CNXN collection just
        # succeeded, the kernel's magic reset lands within ~2-50 s and the
        # xfers only time out against the loader (~3 min per cycle wasted).
        if [ "$CNXN_OK" = "1" ]; then
          log "c$c: skip ring xfer (cnxn collection ok)"
        else
          rm -f "rings_night/ring_c${c}.bin"
          if timeout 60 "$UV" run --with pyusb --no-project python3 fb_xfer.py r 348d0000 8000 "rings_night/ring_c${c}.bin" >>"$LOG" 2>&1; then
            log "c$c: ring xfer $(stat -c %s "rings_night/ring_c${c}.bin" 2>/dev/null) bytes"
          else
            log "c$c: ring xfer failed"
          fi
        fi
        bash boot_ledger.py >>"$LOG" 2>&1 || true'''

if old_xfer not in src:
    sys.exit("xfer block anchor missing")
src = src.replace(old_xfer, new_xfer)

for old, new in reps:
    if old not in src:
        sys.exit(f"anchor missing: {old[:50]}")
    src = src.replace(old, new)

open("night_engine_v13.sh", "w").write(src)
print("night_engine_v13.sh written:", len(src), "bytes")
