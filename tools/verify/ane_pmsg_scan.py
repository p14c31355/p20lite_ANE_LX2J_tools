#!/usr/bin/env python3
"""Parse the pmsg record the pmsg-dump probe appends, once root pulls it out.

The record (128 bytes) is appended by ane_pmsg_dump.S at zone + 12 + size:
    +0    8 bytes  "ANEPv1->"  (marker)
    +8   96 bytes  the raw 24-entry [step, value] trace of the previous
                   bare-metal probe (TRACE_BASE 0x348c0000)
    +104 24 bytes  the step-mark block (magic, count, marks)

Usage: ane_pmsg_scan.py usb_runs/pmsg.bin
"""
import struct
import sys
import pathlib

MARKER = b"ANEPv1->"


def main():
    path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "usb_runs/pmsg.bin")
    data = path.read_bytes()
    print(f"file: {path}  {len(data)} bytes")

    # the zone header first: {sig, start, size}
    if len(data) >= 12:
        sig, start, size = struct.unpack_from("<III", data, 0)
        print(f"zone header: sig=0x{sig:08x} ({'DBGC ok' if sig == 0x43474244 else 'NOT DBGC'}) start={start} size={size}")
        if size > len(data) - 12:
            print(f"  (note: header size {size} exceeds the pulled data; the file may be truncated)")

    print()
    found = 0
    off = 0
    while True:
        i = data.find(MARKER, off)
        if i < 0:
            break
        found += 1
        print(f"== record at file offset {i} (marker {'at data start' if i == 12 else 'mid-zone'}) ==")
        body = data[i + 8: i + 8 + 120]
        if len(body) < 120:
            print("  (record truncated)")
            off = i + 1
            continue
        words = struct.unpack_from("<24I", body, 0)
        print("  trace (24 words, [step, value] pairs):")
        for k in range(0, 24, 2):
            s, v = words[k], words[k + 1]
            print(f"    entry {k // 2:2d}: step={s:4d} value=0x{v:08x}")
        magic, count = struct.unpack_from("<II", body, 96)
        marks = body[104:104 + min(count, 16)]
        print(f"  marks: magic=0x{magic:08x} ({'ANEM' if magic == 0x4D454E41 else 'not ANEM'}) count={count}")
        print(f"         {marks!r}")
        print()
        off = i + 1

    if not found:
        print("no ANEPv1-> marker found. The record may not have survived, or the")
        print("pmsg zone was re-initialised. Compare 'size' above with the expected")
        print("append (the probe added 128 bytes).")


if __name__ == "__main__":
    main()
