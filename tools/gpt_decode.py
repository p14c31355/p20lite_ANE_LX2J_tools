#!/usr/bin/env python3
"""Decode the em: ge_* GPT-entry log lines into a partition table.

Each logged value is `(entry_index << 32) | datum`:
  ge_t  = type GUID, first 32-bit word (0xEBD0A0A2 = Microsoft Basic Data)
  ge_s  = first LBA
  ge_n0..ge_n4 = the first ten UTF-16LE name bytes (5 words)
"""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/olog_main.txt"
entries = {}
for line in open(path, "r", errors="replace"):
    m = re.search(r"(?:INFO)?EM: GE_([TSN0-4]+)=0X([0-9A-F]+)", line.upper())
    if not m:
        continue
    field, value = m.group(1), int(m.group(2), 16)
    idx = value >> 32
    datum = value & 0xFFFFFFFF
    entries.setdefault(idx, {})[field] = datum

print(f"{'idx':>3} {'type':>10} {'startLBA':>10}  name")
for idx in sorted(entries):
    e = entries[idx]
    words = [e.get(f"N{i}", 0) for i in range(5)]
    chars = []
    for w in words:
        for half in (w & 0xFFFF, (w >> 16) & 0xFFFF):
            chars.append(chr(half) if 32 <= half < 127 else ("" if half == 0 else "."))
    name = "".join(chars).split("\x00")[0]
    print(
        f"{idx:>3} 0x{e.get('T', 0):08X} {e.get('S', 0):>10}  {name}"
    )
