#!/usr/bin/env python3
"""Find every UPDATE.APP block header by scanning for the magic everywhere.

The jump-based parser (pos = header + payload) loses blocks: this file has large
gaps between the headers it *did* find, so the real table must have entries my
filter or my jump skipped. A 4-byte magic appears by chance about once in 4 GB,
so listing every hit is safe.

Relaxed header-size ceiling (65536) because big partition images appear to carry
larger headers than the small ones (which were 100..3200 bytes).

Also extracts any KERNEL/RAMDISK/RECOVERY_RAMDISK payload it finds, then runs
vmlinux-to-elf over the kernel so we can read the two addresses the exploit
hardcodes.
"""
import os
import struct
import subprocess
import sys

APP = sys.argv[1] if len(sys.argv) > 1 else "/tmp/app/UPDATE.APP"
MAGIC = b"\x55\xaa\x5a\xa5"
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/kern"
os.makedirs(OUT, exist_ok=True)

data = open(APP, "rb").read()
print(f"file: {len(data):,} bytes")

hits = []
pos = 0
while True:
    j = data.find(MAGIC, pos)
    if j == -1:
        break
    if j + 100 <= len(data):
        hdr_sz, unk1, hw_id, seq, size = struct.unpack("<IIQII", data[j+4:j+28])
        ptype = data[j+60:j+76].decode("ascii", "replace").strip("\x00")
        printable = all(32 <= ord(c) < 127 for c in ptype) and 1 <= len(ptype) <= 16
        if printable and 50 <= hdr_sz <= 65536 and size <= 5_000_000_000:
            hits.append((j, hdr_sz, size, ptype))
    pos = j + 1

prev_end = 0
for i, (j, h, s, t) in enumerate(hits):
    gap = j - prev_end
    print(f"[{i:>3}] @{j:#012x} {t:<18} hdr={h:<6} size={s:>13,}  gap={gap:>12,}")
    prev_end = j + h + s
print(f"total headers: {len(hits)}")

names = {t.upper() for _, _, _, t in hits}
print("names:", sorted(names))

wanted = {"KERNEL", "RAMDISK", "RECOVERY_RAMDISK", "KERNEL_IMAGE"}
for (j, h, s, t) in hits:
    if t.upper() in wanted:
        path = f"{OUT}/{t.lower()}.img"
        with open(path, "wb") as f:
            f.write(data[j+h:j+h+s])
        print(f"wrote {path} ({s:,} bytes)")

kern = f"{OUT}/kernel.img"
if os.path.exists(kern):
    print("\n### vmlinux-to-elf")
    r = subprocess.run(["/home/placeless/dev/p20-root/.venv-sym/bin/vmlinux-to-elf", kern,
                        f"{OUT}/kernel.elf"],
                       capture_output=True, text=True, timeout=600)
    print(r.stdout[-2000:])
    print(r.stderr[-1000:])
    if os.path.exists(f"{OUT}/kernel.elf"):
        print("\n### looking up the symbols the exploit hardcodes")
        for sym in ("fair_sched_class", "avc_cache", "selinux_state",
                    "selinux_enforcing", "kallsyms_offsets"):
            rr = subprocess.run(["nm", f"{OUT}/kernel.elf"], capture_output=True, text=True)
            line = [l for l in rr.stdout.splitlines() if l.endswith(" " + sym)]
            print(f"  {sym:20} {line[0] if line else 'not found'}")
else:
    print("\nno KERNEL block extracted")
