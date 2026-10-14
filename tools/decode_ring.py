#!/usr/bin/env python3
"""Decode one rings_night dump by SEGMENT: the ring holds several boots'
appends, so split it at the boot-start markers and report the LAST segment
(the current boot) plus a summary of each segment."""
import re
import sys

path = sys.argv[1]
data = open(path, "rb").read()
raw = int.from_bytes(data[4:8], "little")
text = data.decode("latin-1")

# Boot boundaries: every "HELLO FROM FULLERENE" starts a new boot's log.
starts = [m.start() for m in re.finditer(r"HELLO FROM FULLERENE", text)]
print(f"== {path}: {len(data)}B raw={raw} boots={len(starts)} ==")
if not starts:
    starts = [0]
ends = starts[1:] + [len(text)]
for si, (s, e) in enumerate(zip(starts, ends)):
    seg = text[s:e]
    marks = re.findall(r"MARK: [^\n\r\x00]{3,48}", seg)
    ul = re.findall(r"USER-LAUNCHD[^\n\r\x00]{0,80}", seg)
    stage = re.findall(r"EM: STAGE=0X[0-9A-F]+", seg)
    last = si == len(starts) - 1
    tag = " <- LAST (current boot)" if last else ""
    print(f"-- seg{si} [{s}..{e}) len={len(seg)}{tag}: stage={stage} marks={len(marks)} ul={len(ul)}")
    for m in marks:
        print("     ", m)
    for u in ul:
        print("     ", u)
    if last:
        tail_at = seg.rfind("USER-LAU")
        ctx = seg[max(0, tail_at - 200):] if tail_at >= 0 else seg[-200:]
        print("     tail:", ctx.replace("\r", "")[:600])
