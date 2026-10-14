#!/usr/bin/env python3
"""Decode `oem scan` output (NZ_LBA / NZ_BM0 / NZ_BM1 / NZ_W lines).

Reconstructs each non-zero sector's sparse words into bytes and prints a
hex + strings view. NZ_W value = (index << 32) | word.
"""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/olog_raw.txt"

re_lba = re.compile(r"NZ_LBA=0X([0-9A-Fa-f]+)")
re_bm = re.compile(r"NZ_BM(\d)=0X([0-9A-Fa-f]+)")
re_w = re.compile(r"NZ_W=0X([0-9A-Fa-f]+)")

sectors = {}
cur = None
for line in open(path, errors="replace"):
    u = line.upper()
    m = re_lba.search(u)
    if m:
        cur = int(m.group(1), 16)
        sectors.setdefault(cur, {})
        continue
    m = re_w.search(u)
    if m and cur is not None:
        v = int(m.group(1), 16)
        idx = v >> 32
        sectors[cur][idx] = v & 0xFFFFFFFF

print(f"# {len(sectors)} non-zero sectors")
for lba in sorted(sectors):
    w = sectors[lba]
    data = bytearray(512)
    for i, v in w.items():
        if i < 128:
            data[i * 4 : i * 4 + 4] = v.to_bytes(4, "big")
    s = "".join(chr(b) if 32 <= b < 127 else "." for b in data)
    strs = [x for x in re.findall(r"[ -~]{4,}", s)]
    print(f"\n=== sector {lba:#x} ({len(w)} nz words) ===")
    if strs:
        for x in sorted(set(strs))[:30]:
            print(f"  str: {x}")
    # hex of the first 64 bytes and nonzero regions
    print(f"  hex0: {bytes(data[:64]).hex()}")
