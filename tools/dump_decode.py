#!/usr/bin/env python3
"""Decode `oem dump` output: "EM: DUMP_LBA=.." starts a sector, then 64
"EM: DD=<16hex>" lines = 8 bytes each (big-endian hex = byte order)."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/olog_main.txt"
cur_lba = None
buf = []
out = []

for line in open(path, "r", errors="replace"):
    m = re.search(r"DUMP_LBA=0X([0-9A-F]+)", line, re.I)
    if m:
        cur_lba = int(m.group(1), 16)
        buf = []
        continue
    m = re.search(r"\bDD=0X([0-9A-F]{1,16})", line, re.I)
    if m and cur_lba is not None:
        v = int(m.group(1), 16)
        buf.extend(v.to_bytes(8, "big"))
        if len(buf) >= 512:
            out.append((cur_lba, bytes(buf[:512])))

for lba, data in out:
    print(f"=== sector LBA 0x{lba:X} ===")
    for off in range(0, 512, 16):
        row = data[off : off + 16]
        hexs = " ".join(f"{b:02x}" for b in row)
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in row)
        print(f"{off:04x}: {hexs}  {text}")
