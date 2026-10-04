#!/usr/bin/env python3
"""Verify base-address computation in a probe ELF, from the built instructions.

Why: the RCH probe shipped with `movz w19, #(BASE >> 16), lsl #16` and no
`movk` for the low half. QEMU's proof used 64 KiB-aligned test bases, so a
wrong runtime address never showed. This check reads the *device* build and
proves which values the register actually holds when used as a load/store base.

Usage: verify_base_loads.py ELF REG VALUE [VALUE...]
  e.g. verify_base_loads.py device.elf w19 0xE8620000 0xE8628000 0xE8638000 0xE8640000

Exits 0 when the set of base values used equals the expected set exactly.
"""
import re
import subprocess
import sys

USAGE = "usage: verify_base_loads.py ELF REG VALUE [VALUE...]"


def parse(lines, reg):
    used = []
    value = None
    low = reg[1:]          # 19
    base_ref = re.compile(rf"\[\s*[wx]{low}\b")
    for line in lines:
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        asm = "\t".join(parts[2:]).strip()
        m = re.match(rf"mov\s+{reg}, #0x([0-9a-f]+)", asm)
        if m:
            value = int(m.group(1), 16) & 0xFFFFFFFF
            continue
        m = re.match(rf"movz\s+{reg}, #0x([0-9a-f]+)(?:, lsl #(\d+))?", asm)
        if m:
            shift = int(m.group(2) or 0)
            value = (int(m.group(1), 16) << shift) & 0xFFFFFFFF
            continue
        m = re.match(rf"movk\s+{reg}, #0x([0-9a-f]+)(?:, lsl #(\d+))?", asm)
        if m:
            shift = int(m.group(2) or 0)
            if value is None:
                value = 0
            value = (value & ~(0xFFFF << shift)) | (int(m.group(1), 16) << shift)
            value &= 0xFFFFFFFF
            continue
        if value is not None and base_ref.search(asm) and re.match(r"(ldr|str|ldp|stp|ldrb|strb|ldrh|strh)\b", asm):
            used.append(value)
    return used


def main():
    if len(sys.argv) < 4:
        print(USAGE)
        return 2
    elf, reg = sys.argv[1], sys.argv[2]
    want = {int(v, 0) for v in sys.argv[3:]}
    dis = subprocess.run(["aarch64-linux-gnu-objdump", "-d", elf],
                         capture_output=True, text=True, check=True).stdout
    used = parse(dis.splitlines(), reg)
    got = set(used)
    ok = got == want
    print(f"  {reg} base values used: {sorted(hex(v) for v in got)}")
    if not ok:
        missing = sorted(hex(v) for v in want - got)
        extra = sorted(hex(v) for v in got - want)
        if missing:
            print(f"    missing: {missing}")
        if extra:
            print(f"    unexpected: {extra}")
        print("  FAIL: base loads do not match the expected set")
    else:
        print("  PASS: every base load computes exactly the intended address")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
