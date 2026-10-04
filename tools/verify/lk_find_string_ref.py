#!/usr/bin/env python3
"""Locate the routine that references a given LK string, by page-context xref.

Context: firmware/lk_asm/lk.asm is a flat disassembly of firmware/fastboot_LK.bin
with base 0x10000000. Strings are reached with adrp <page> + add <reg>, #<offset>
pairs, so a string at file offset F (vaddr 0x10000000+F) is referenced by an
"adrp x?, <vaddr page>" followed within a few instructions by
"add x?, x?, #<offset-in-page>". This script finds those sites and reports the
enclosing function (walking back to the standard prologue).
"""
import re
import sys
import pathlib

ASM = pathlib.Path("firmware/lk_asm/lk.asm")
BASE = 0x10000000


def main():
    if len(sys.argv) < 2:
        print("usage: lk_find_string_ref.py <file-offset-hex> [more offsets]")
        return 1
    lines = ASM.read_text(errors="replace").splitlines()
    # index instruction lines by address
    insn = []            # (addr, text, line_index)
    for idx, line in enumerate(lines):
        m = re.match(r"\s*([0-9a-f]{8}):\s+([0-9a-f]{8})\s+(.*)", line)
        if m:
            insn.append((int(m.group(1), 16), m.group(3), idx))
    for arg in sys.argv[1:]:
        off = int(arg, 16)
        vaddr = BASE + off
        page = vaddr & ~0xFFF
        off_in_page = vaddr & 0xFFF
        print(f"== string file offset {off:#x} -> vaddr {vaddr:#x} "
              f"(page {page:#x} + {off_in_page:#x})")
        hits = 0
        for i, (addr, text, idx) in enumerate(insn):
            if "adrp" not in text:
                continue
            m = re.search(r"adrp\s+x\d+, 0x([0-9a-f]+)", text)
            if not m or int(m.group(1), 16) != page:
                continue
            # look ahead a few instructions for the add with our offset
            for j in range(i, min(i + 4, len(insn))):
                t = insn[j][1]
                m2 = re.search(r"add\s+x\d+, x\d+, #0x([0-9a-f]+)", t)
                if m2 and int(m2.group(1), 16) == off_in_page:
                    a = insn[j][0]
                    # walk back to the prologue (stp x29, x30, [sp, #-...]!)
                    func = None
                    for k in range(j, max(0, j - 400), -1):
                        if "stp\tx29, x30, [sp, #-" in insn[k][1]:
                            func = insn[k][0]
                            break
                    print(f"   xref at {a:#x}  (enclosing prologue ~{func:#x if func else 0}")
                    hits += 1
        if not hits:
            print("   (no adrp+add pair found; the string may be reached indirectly)")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
