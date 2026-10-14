#!/usr/bin/env python3
"""Decode the v213 step-markers file (fb_xfer r 348df000 40).

Layout (entry.rs StepMarks): u32 at +0 (magic/ours), u32 at +4 = count,
16 bytes at +8. Prints the count and the byte trail as characters.
"""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "forensics/marks_c1.bin"
data = open(path, "rb").read()
print(f"{path}: {len(data)} bytes")
if len(data) < 24:
    print("raw:", data.hex())
    sys.exit(0)

magic = int.from_bytes(data[0:4], "little")
count = int.from_bytes(data[4:8], "little")
print(f"word0(+0)=0x{magic:08x}  count(+4)={count}")
if count > 16:
    print(f"count out of range ({count}); dumping window: {data[:32].hex()}")
    sys.exit(0)
trail = data[8:8 + count]
print("trail:", "".join(chr(b) if 32 <= b < 127 else f"[{b:02x}]" for b in trail))
rest = data[8 + count:8 + 16]
print("rest :", "".join(chr(b) if 32 <= b < 127 else f"[{b:02x}]" for b in rest) if rest.strip(b"\x00") else "(empty)")
