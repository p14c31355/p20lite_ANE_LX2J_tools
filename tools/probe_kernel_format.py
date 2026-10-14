#!/usr/bin/env python3
"""What format does the ANE-LX2J bootloader expect in the kernel partition?

An uncompressed arm64 Linux Image carries the magic b"ARM\\x64" at offset 0x38 and
a branch instruction at offset 0. A gzip'd image starts 1f 8b; an lz4 frame starts
04 22 4d 18.
"""
import gzip
import struct
import sys

GZIP_MAGIC = b"\x1f\x8b"
LZ4_MAGIC = b"\x04\x22\x4d\x18"
ARM64_MAGIC = b"ARM\x64"


def probe(path):
    try:
        d = open(path, "rb").read()
    except FileNotFoundError:
        print(f"{path}: not found")
        return
    print(f"== {path}  ({len(d):,} bytes)")
    print(f"   first 16 bytes : {d[:16].hex()}")
    print(f"   gzip           : {d[:2] == GZIP_MAGIC}")
    print(f"   lz4 frame      : {d[:4] == LZ4_MAGIC}")
    body = d
    if d[:2] == GZIP_MAGIC:
        try:
            body = gzip.decompress(d)
            print(f"   decompressed   : {len(body):,} bytes, first 16 = {body[:16].hex()}")
        except Exception as e:
            print(f"   gzip decompress failed: {e}")
            return
    if len(body) >= 64:
        code0, code1, text_off, size = struct.unpack("<IIQQ", body[0:24])
        magic = body[0x38:0x3c]
        print(f"   code0 @0x00    : {code0:#010x}  (arm64 Linux Image: 0x14000010 typical)")
        print(f"   code1 @0x04    : {code1:#010x}  (0xd503201f = nop)")
        print(f"   text_offset    : {text_off:#x}")
        print(f"   image_size     : {size:#x} ({size:,})")
        ok = magic == ARM64_MAGIC
        print(f"   magic @0x38    : {magic!r}  {'ARM64 Image OK' if ok else 'NOT an arm64 Image header'}")
    print()


for p in sys.argv[1:]:
    probe(p)
