#!/usr/bin/env python3
"""Work out the frp partition's format from the dump we took.

The layout we see:
    0x00  32 bytes of what looks like a digest
    0x20  magic 0x73189019   (AOSP PersistentDataBlock)
    0x24  4 zero bytes       (total_size? or a flag field)
    0x28  a protobuf-looking structure (0a 4b 08 8a 4f 10 20 1a 20 <32 bytes>)
    0x... then a large mostly-zero region

If the leading 32 bytes are a hash of what follows, we can recompute it and write
a modified block that still verifies. Test that hypothesis here.
"""
import hashlib

DATA = "firmware/partitions/frp.bin"
d = open(DATA, "rb").read()
print(f"partition size: {len(d):,} bytes")
print(f"first 32 : {d[:32].hex()}")
print(f"magic    : 0x{int.from_bytes(d[0x20:0x24], 'little'):08x}  (AOSP PDB magic = 0x73189019)")
print(f"at 0x24  : {d[0x24:0x28].hex()}  = {int.from_bytes(d[0x24:0x28], 'little')}")
print()

first = d[:32]
candidates = {
    "sha256(whole file)": hashlib.sha256(d).digest(),
    "sha256(from 0x20 to end)": hashlib.sha256(d[0x20:]).digest(),
    "sha256(from 0x20, 0x80 bytes)": hashlib.sha256(d[0x20:0xA0]).digest(),
    "sha256(from 0x20, 0x100)": hashlib.sha256(d[0x20:0x120]).digest(),
    "sha256(from 0x20, 0x200)": hashlib.sha256(d[0x20:0x220]).digest(),
    "sha256(from 0x24 to end)": hashlib.sha256(d[0x24:]).digest(),
    "sha256(0x00..0x1F zeroed)": hashlib.sha256(b"\0" * 32 + d[32:]).digest(),
}
for name, h in candidates.items():
    print(f"{name:36} -> {h.hex()[:32]}...  {'MATCH' if h == first else ''}")

print()
# where are the non-zero regions?
nz = [i for i, b in enumerate(d) if b != 0]
print(f"non-zero bytes: {len(nz)} of {len(d)}")
if nz:
    print(f"first non-zero: 0x{nz[0]:x}   last non-zero: 0x{nz[-1]:x}")
    # cluster them
    runs, start, prev = [], nz[0], nz[0]
    for i in nz[1:]:
        if i - prev > 16:
            runs.append((start, prev))
            start = i
        prev = i
    runs.append((start, prev))
    print("regions with data:")
    for a, b in runs[:12]:
        print(f"  0x{a:05x} .. 0x{b:05x}  ({b - a + 1} bytes)  {d[a:a+24].hex()}")

print()
print("bytes at 0x20..0x60:")
for off in range(0x20, 0x60, 16):
    print(f"  {off:04x}: {d[off:off+16].hex()}")
