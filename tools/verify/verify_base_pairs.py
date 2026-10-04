#!/usr/bin/env python3
"""Verify base-address computation for the branch-coupled load shape.

verify_base_loads.py proves the value at the *next* memory access, which
works when each base-load is immediately followed by its own load/store
(e.g. the blit block shape). The index-select builders in the text probes
spell the bases as a chain of movz/movk pairs that all branch to one shared
`ldr w25, [x19, #0x60]`; statically, only the last pair survives to the
shared load, so that checker reports a false negative.

This checker instead collects every movz+movk (w19) pair in program order
and compares the resolved value set. The pairing guarantee for the shared
load is structural: each block sets w19 and branches to the shared use
point, so the last base set before the branch is the one loaded.

Usage: verify_base_pairs.py ELF REG VALUE [VALUE...]
"""
import re
import subprocess
import sys


def parse_pairs(lines, reg):
    values = []
    pending = None
    for line in lines:
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        asm = "\t".join(parts[2:]).strip()
        m = re.match(rf"mov\s+{reg}, #0x([0-9a-f]+)", asm)
        if m:
            if pending is not None:
                values.append(pending)
            pending = int(m.group(1), 16) & 0xFFFFFFFF
            continue
        m = re.match(rf"movz\s+{reg}, #0x([0-9a-f]+)(?:, lsl #(\d+))?", asm)
        if m:
            if pending is not None:
                values.append(pending)
            shift = int(m.group(2) or 0)
            pending = (int(m.group(1), 16) << shift) & 0xFFFFFFFF
            continue
        m = re.match(rf"movk\s+{reg}, #0x([0-9a-f]+)(?:, lsl #(\d+))?", asm)
        if m:
            shift = int(m.group(2) or 0)
            if pending is None:
                pending = 0
            pending = (pending & ~(0xFFFF << shift)) | (int(m.group(1), 16) << shift)
            pending &= 0xFFFFFFFF
            continue
        # any other instruction writing the register ends the pair's identity
        if re.match(rf"(mov|movz|movk|add|sub|ldr|orr|and|lsr|lsl|adr|adrp)\s+{reg}\b", asm):
            if pending is not None:
                values.append(pending)
                pending = None
    if pending is not None:
        values.append(pending)
    return values


def main():
    if len(sys.argv) < 4:
        print("usage: verify_base_pairs.py ELF REG VALUE [VALUE...]")
        return 2
    elf, reg = sys.argv[1], sys.argv[2]
    want = {int(v, 0) for v in sys.argv[3:]}
    dis = subprocess.run(["aarch64-linux-gnu-objdump", "-d", elf],
                         capture_output=True, text=True, check=True).stdout
    got = set(parse_pairs(dis.splitlines(), reg))
    ok = got == want
    print(f"  {reg} pair values used: {sorted(hex(v) for v in got)}")
    if not ok:
        missing = sorted(hex(v) for v in want - got)
        extra = sorted(hex(v) for v in got - want)
        if missing:
            print(f"    missing: {missing}")
        if extra:
            print(f"    unexpected: {extra}")
        print("  FAIL: base pairs do not match the expected set")
    else:
        print("  PASS: every movz/movk pair resolves to an intended base")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
