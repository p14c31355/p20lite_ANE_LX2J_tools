#!/usr/bin/env python3
"""Diagnose the dump blocks in a raw capture: per DUMP_LBA, count DD lines
and show the byte summary."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/olog_raw.txt"
re_lba = re.compile(r"DUMP_LBA=0X([0-9A-Fa-f]+)")
re_dd = re.compile(r"DD=0X([0-9A-Fa-f]+)")

blocks = []  # (lba, [hex16 strings])
cur = None
for line in open(path, errors="replace"):
    m = re_lba.search(line)
    if m:
        cur = (int(m.group(1), 16), [])
        blocks.append(cur)
        continue
    m = re_dd.search(line)
    if m and cur is not None:
        cur[1].append(m.group(1))

print(f"total DUMP_LBA blocks: {len(blocks)}")
for lba, dds in blocks:
    data = b"".join(bytes.fromhex(h.zfill(16)[:16]) for h in dds)
    nz = sum(1 for i in range(0, len(data), 4) if data[i : i + 4] != b"\x00\x00\x00\x00")
    print(f"lba {lba:#09x}: {len(dds):3d} dd lines, {len(data):4d} bytes, nz_words={nz:3d}")
    if nz and len(data) >= 64:
        print(f"         head: {data[:48].hex()}")
        s = "".join(chr(b) if 32 <= b < 127 else "." for b in data[:256])
        if any(c.isalnum() for c in s):
            print(f"         text: {s}")
