#!/usr/bin/env python3
"""Scan a raw RAM dump of the ANE-LX2J's reserved windows for our structures.

Dump convention (ane_root_dump.sh): file starts at physical 0x34000000.

Targets:
  * the step-mark block  @ 0x348df000  magic "ANEM" + count + bytes
  * the trace slot       @ 0x348c0000  12+ [step u32, value u32] pairs
  * the black box ring header "FBLX" (u64 0x46424c58_00000001) if one ever armed
  * pstore zones         persistent_ram "DBGC" headers + readable text
  * bbox text            any printable ASCII runs at least 24 chars long
"""
import struct
import sys
import pathlib

BASE = 0x34000000

def u32(d, off):
    return struct.unpack_from("<I", d, off)[0]

def main():
    path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "usb_runs/ram_34.bin")
    d = path.read_bytes()
    print(f"dump: {path}  {len(d)} bytes  covering 0x{BASE:X}..0x{BASE+len(d):X}")

    def at(phys):
        return phys - BASE

    print()
    print("== trace slot 0x348c0000 (expect step 1..12 with the key reads) ==")
    off = at(0x348C0000)
    if 0 <= off <= len(d) - 96:
        pairs = [struct.unpack_from("<II", d, off + 8 * i) for i in range(12)]
        for i, (s, v) in enumerate(pairs):
            print(f"  entry {i:2d}: step={s:3d} value=0x{v:08x}")
    else:
        print("  out of range")

    print()
    print("== step-mark block 0x348df000 ==")
    off = at(0x348DF000)
    if 0 <= off <= len(d) - 8:
        magic, count = struct.unpack_from("<II", d, off)
        marks = d[off + 8: off + 8 + min(count, 16)]
        print(f"  magic=0x{magic:08x} ({'ANEM' if magic == 0x4D454E41 else 'not ANEM'}) count={count}")
        print(f"  marks={marks!r}")
    else:
        print("  out of range")

    print()
    print("== ring magic FBLX scan ==")
    needle = struct.pack("<Q", 0x46424C5800000001)
    found = []
    start = 0
    while True:
        i = d.find(needle, start)
        if i < 0:
            break
        found.append(i)
        start = i + 1
    for i in found[:10]:
        print(f"  at 0x{BASE + i:X}")
    if not found:
        print("  none")

    print()
    print("== pstore persistent_ram headers (DBGC) ==")
    n = 0
    start = 0
    while True:
        i = d.find(b"DBGC", start)
        if i < 0:
            break
        if i + 12 <= len(d):
            sig, s2, size = struct.unpack_from("<III", d, i)
            print(f"  0x{BASE + i:X}: sig=0x{sig:08x} start=0x{s2:x} size=0x{size:x}")
            n += 1
        start = i + 4
    if n == 0:
        print("  none")

    print()
    print("== long printable runs (>= 24 chars, text worth reading) ==")
    run_start = None
    out = []
    for i, byte in enumerate(d):
        printable = 32 <= byte < 127
        if printable and run_start is None:
            run_start = i
        elif not printable and run_start is not None:
            if i - run_start >= 24:
                out.append((run_start, i))
            run_start = None
    for s, e in out[:40]:
        text = d[s:e].decode("ascii", "replace")
        print(f"  0x{BASE + s:X}: {text[:100]}")
    if not out:
        print("  none")

if __name__ == "__main__":
    main()
