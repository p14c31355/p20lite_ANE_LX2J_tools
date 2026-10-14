#!/usr/bin/env python3
"""Look up a runtime PC in the ANE kernel image's symbols.

The kernel is a static PIE loaded at 0x480000 (the image header's
kernel_addr); this maps the runtime PC back to the ELF vaddr and prints the
nearest symbol with an offset.

Usage: pc_lookup.py <hex-pc> [path/to/fullerene-kernel]
"""
import re
import subprocess
import sys

if len(sys.argv) < 2:
    print(__doc__)
    sys.exit(1)

BIN = (
    sys.argv[2]
    if len(sys.argv) > 2
    else "target/manual-ane-launchd/aarch64-unknown-none/release/fullerene-kernel"
)
pc = int(sys.argv[1].replace("0x", ""), 16)

out = subprocess.run(["readelf", "-lW", BIN], capture_output=True, text=True).stdout
vaddrs = []
for m in re.finditer(r"LOAD\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)", out):
    vaddrs.append(int(m.group(2), 16))
base = min(vaddrs) if vaddrs else 0
delta = 0x480000 - base
elf_pc = pc - delta
print(f"runtime pc {pc:#x} -> elf vaddr {elf_pc:#x} (elf base {base:#x}, delta {delta:#x})")

out = subprocess.run(["nm", "-nC", BIN], capture_output=True, text=True).stdout
best = None
for line in out.splitlines():
    parts = line.split(" ", 2)
    if len(parts) < 3:
        continue
    try:
        addr = int(parts[0], 16)
    except ValueError:
        continue
    if addr <= elf_pc:
        best = (addr, parts[2])
    else:
        break
if best:
    print(f"symbol: {best[1]} + {elf_pc - best[0]:#x}")
else:
    print("no symbol found")
