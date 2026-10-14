#!/usr/bin/env python3
"""v14 engine transform: night_engine_v13.sh -> night_engine_v14.sh

The ~4 min ProgressWatchdog death (us-based, self-clocked ~3.9x race) limits
boots to ~230 s from start. A recovered boot's clean event lands ~+100 s;
v13's ~130 s settle put the collection attempt at ~+235 s - just missing.
v14: settle 25 x 3 s (~75-80 s real) so the attempt starts ~+180 s.
"""
import sys

src = open("night_engine_v13.sh").read()

reps = [
    ('log "=== night engine v13 start img=$IMG cycles=$CYCLES ==="',
     'log "=== night engine v14 start img=$IMG cycles=$CYCLES ==="'),
    ('log "=== night engine v13 done ==="',
     'log "=== night engine v14 done ==="'),
    ('        for _s in $(seq 1 40); do',
     '        for _s in $(seq 1 25); do'),
]

for old, new in reps:
    if old not in src:
        sys.exit(f"anchor missing: {old[:60]}")
    src = src.replace(old, new)

open("night_engine_v14.sh", "w").write(src)
print("night_engine_v14.sh written:", len(src), "bytes")
