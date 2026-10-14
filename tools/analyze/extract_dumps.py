#!/usr/bin/env python3
"""Extract `oem dump` sectors from a raw ring capture.

Scans for "DUMP_LBA=0X<hex>" then collects the following "DD=0X<16hex>"
lines (8 bytes each, 64 per sector). Prints per-LBA: hex dump + printable
strings. Multiple copies (reader restarts) are deduped by keeping the
first complete copy per LBA.
"""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/olog_raw.txt"
want = set()
if len(sys.argv) > 2:
    for a in sys.argv[2:]:
        want.add(int(a, 16))

sectors = {}  # lba -> bytes (first complete copy)
lba = None
buf = bytearray()
re_lba = re.compile(r"DUMP_LBA=0X([0-9A-Fa-f]+)")
re_dd = re.compile(r"DD=0X([0-9A-Fa-f]{16})")

for line in open(path, errors="replace"):
    m = re_lba.search(line)
    if m:
        if lba is not None and len(buf) == 512 and lba not in sectors:
            sectors[lba] = bytes(buf)
        lba = int(m.group(1), 16)
        buf = bytearray()
        continue
    m = re_dd.search(line)
    if m and lba is not None:
        buf += bytes.fromhex(m.group(1))

if lba is not None and len(buf) == 512 and lba not in sectors:
    sectors[lba] = bytes(buf)

print(f"# sectors found: {len(sectors)}")
for k in sorted(sectors):
    print(f"{k:#x}", end=" ")
print()

for k in sorted(sectors):
    if want and k not in want:
        continue
    data = sectors[k]
    print(f"\n=== sector {k:#x} ===")
    print(f"hex: {data[:64].hex()}")
    # printable strings (>=4 chars)
    s = "".join(chr(b) if 32 <= b < 127 else "." for b in data)
    for i in range(0, len(s), 64):
        chunk = s[i : i + 64]
        if chunk.strip("."):
            print(f"{i:04x}: {chunk}")
    # non-zero word map
    nz = [i for i in range(0, 512, 4) if data[i : i + 4] != b"\x00\x00\x00\x00"]
    if nz:
        print(f"nonzero words at: {[hex(x) for x in nz[:40]]}{'...' if len(nz) > 40 else ''}")
