#!/usr/bin/env python3
"""Parse the Android boot image header in the ANE-LX2J kernel partition.

The LK boots whatever the kernel partition holds, and the header tells us the
contract Fullerene's aarch64 image has to satisfy:
  - kernel load address and entry conditions
  - page size, cmdline, tags address
  - what the ramdisk/dtb fields are set to (Huawei splits those into their own
    partitions, so they may be zero)
"""
import struct

ARM64_MAGIC = b"ARM\x64"
import sys

FIELDS = [
    ("kernel_size", 0x08, "I"),
    ("kernel_addr", 0x0C, "I"),
    ("ramdisk_size", 0x10, "I"),
    ("ramdisk_addr", 0x14, "I"),
    ("second_size", 0x18, "I"),
    ("second_addr", 0x1C, "I"),
    ("tags_addr", 0x20, "I"),
    ("page_size", 0x24, "I"),
    ("header_version", 0x28, "I"),
    ("os_version", 0x2C, "I"),
]


def parse(path):
    d = open(path, "rb").read()
    print(f"== {path} ({len(d):,} bytes)")
    magic = d[:8]
    print(f"   magic        : {magic!r}")
    if magic != b"ANDROID!":
        print("   not an Android boot image")
        return
    vals = {}
    for name, off, fmt in FIELDS:
        v = struct.unpack_from("<" + fmt, d, off)[0]
        vals[name] = v
        print(f"   {name:15}: {v:#010x} ({v:,})")
    name = d[0x30:0x40].split(b"\0")[0]
    print(f"   name         : {name!r}")
    cmd = d[0x40:0x240].split(b"\0")[0]
    print(f"   cmdline      : {cmd!r}")
    extra = d[0x248:0x248+1024].split(b"\0")[0]
    if extra:
        print(f"   extra cmdline: {extra!r}")
    ps = vals["page_size"] or 2048
    ksz = vals["kernel_size"]
    print()
    print(f"   kernel payload: {ksz:,} bytes starting at {ps:#x}")
    # arm64 Image header inside the payload?
    start = ps
    payload = d[start:start + ksz]
    if len(payload) >= 64:
        code0, code1 = struct.unpack_from("<II", payload, 0)
        magic64 = payload[0x38:0x3c]
        is_img = magic64 == ARM64_MAGIC
        print(f"   payload head : {payload[:16].hex()}")
        print(f"   code0        : {code0:#010x}")
        print(f"   arm64 magic  : {magic64!r} {'ARM64 Image OK' if is_img else 'not a linux Image header'}")
        if payload[:2] == b"\x1f\x8b":
            print("   payload is gzip-compressed")
        elif payload[:4] == b"\x04\x22\x4d\x18":
            print("   payload is an lz4 frame")
    print()


for p in sys.argv[1:]:
    parse(p)
