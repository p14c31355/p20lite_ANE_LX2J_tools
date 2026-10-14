#!/usr/bin/env python3
"""Cycle-time breakdown from the night-engine log.

Parses the [MMDD HH:MM:SS] stamped engine log and derives, per boot cycle:
  flash -> attach  (kernel start + enumeration)
  attach -> collect (settle + CNXN)
  collect -> next flash (reset + LK + flash gap)
and prints the per-cycle timeline plus averages.
"""
import re
import sys
from datetime import datetime

path = sys.argv[1] if len(sys.argv) > 1 else None
if path is None:
    import glob
    import os
    cands = sorted(glob.glob("logs/night_*.log"), key=os.path.getmtime)
    path = cands[-1] if cands else None
if path is None:
    print("no log found")
    sys.exit(1)

RE_TS = re.compile(r"^\[(\d{4}) (\d\d:\d\d:\d\d)\] (.*)$")
formats = ("%m%d %H:%M:%S",)

events = []  # (ts, kind, detail)
pending_attach = None
pending_flash = None
pending_collect = None

def parse_ts(d, t):
    return datetime.strptime(f"{d} {t}", "%m%d %H:%M:%S")

for line in open(path, errors="replace"):
    m = RE_TS.match(line.strip())
    if not m:
        continue
    day, tstr, msg = m.group(1), m.group(2), m.group(3)
    ts = parse_ts(day, tstr)
    if "flashed + rebooted" in msg:
        events.append((ts, "flash", ""))
    elif "attach in flight; waiting for product" in msg:
        events.append((ts, "attach", ""))
    elif "ring " in msg and "bytes (attempt" in msg:
        events.append((ts, "collect", msg))
    elif "garbled product; skip" in msg:
        events.append((ts, "garbled-skip", ""))
    elif "product-less attach; skip" in msg:
        events.append((ts, "prodless-skip", ""))
    elif "no product but descriptors" in msg:
        events.append((ts, "desc-fallback", msg))
    elif "adb attempt" in msg or "attempt" in msg and "failed" in msg:
        events.append((ts, "cnxn-fail", msg))

print(f"log: {path}")
print(f"{len(events)} events")
print()
prev_flash = None
attach = None
collect = None
rows = []
for ts, kind, detail in events:
    if kind == "flash":
        prev_flash = ts
    elif kind == "attach":
        attach = ts
    elif kind in ("collect", "garbled-skip", "prodless-skip", "desc-fallback"):
        if prev_flash is not None and attach is not None:
            d_start = (attach - prev_flash).total_seconds()
        else:
            d_start = None
        outcome = kind
        d_collect = None
        if kind == "collect" and attach is not None:
            d_collect = (ts - attach).total_seconds()
        rows.append((prev_flash, attach, ts, outcome, d_start, d_collect))

last_flashs = [r[0] for r in rows if r[0]]
prev_flash_cycle = None
print("cycle timeline (flash -> attach -> outcome):")
tot = []
for i, (fl, at, ts, outcome, d_start, d_collect) in enumerate(rows):
    # flash->flash gap = previous row's outcome to this flash
    gap = ""
    if fl is not None and i > 0:
        # the previous outcome ts is rows[i-1][2]
        g = (fl - rows[i - 1][2]).total_seconds()
        gap = f" gap={g:5.0f}s"
        tot.append(g)
    ds = f"{d_start:5.0f}s" if d_start is not None else "  ?  "
    dc = f"{d_collect:5.0f}s" if d_collect is not None else "  -  "
    print(f"  {fl} start={ds} collect={dc} {outcome}{gap}")
    if d_collect is not None:
        tot.append(d_collect)

if tot:
    print()
    print(f"segments: n={len(tot)} avg={sum(tot)/len(tot):.0f}s min={min(tot):.0f}s max={max(tot):.0f}s")
