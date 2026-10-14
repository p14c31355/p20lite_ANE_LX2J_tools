#!/usr/bin/env python3
"""Wrap a Fullerene aarch64 image in the ANE-LX2J boot image format.

The device's kernel partition holds an Android v0 boot image whose header was
measured from the stock kernel (firmware/kernel_stock.bin):

    kernel_addr  0x00480000      the LK loads the kernel here
    tags_addr    0x07e00000
    page_size    2048
    ramdisk_size 0               Huawei keeps the ramdisk in its own partition
    cmdline      (the stock one, reproduced below)

The stock payload is gzip-compressed, so payloads can be emitted either raw or
gzipped. Which one the LK accepts is an experiment, hence the flag.

Usage:
    mkane_bootimg.py <fullerene.Image> <out.img> [--gzip] [--cmdline "..."]
"""
import gzip
import struct
import sys
from pathlib import Path

KERNEL_ADDR = 0x00480000
TAGS_ADDR = 0x07E00000
PAGE_SIZE = 2048
STOCK_CMDLINE = (
    b"loglevel=4 coherent_pool=512K page_tracker=on slub_min_objects=12 "
    b"unmovable_isolate1=2:192M,3:224M,4:256M printktimer=0xfff0a000,0x534,0x538 "
    b"androidboot.selinux=enforcing buildvariant=user"
)


def pad(data: bytes) -> bytes:
    rem = len(data) % PAGE_SIZE
    return data + b"\0" * (PAGE_SIZE - rem) if rem else data


def build(payload: bytes, cmdline: bytes, gzipped: bool) -> bytes:
    if gzipped:
        payload = gzip.compress(payload, 9)
    header = bytearray()
    header += b"ANDROID!"
    header += struct.pack("<I", len(payload))          # kernel_size
    header += struct.pack("<I", KERNEL_ADDR)           # kernel_addr
    header += struct.pack("<I", 0)                     # ramdisk_size
    header += struct.pack("<I", 0x08000000)            # ramdisk_addr (unused)
    header += struct.pack("<I", 0)                     # second_size
    header += struct.pack("<I", 0x01300000)            # second_addr
    header += struct.pack("<I", TAGS_ADDR)             # tags_addr
    header += struct.pack("<I", PAGE_SIZE)             # page_size
    header += struct.pack("<I", 0)                     # header_version
    header += struct.pack("<I", 0x10000133)            # os_version
    header += b"\0" * 16                               # name
    cmd = cmdline[:512]
    header += cmd + b"\0" * (512 - len(cmd))           # cmdline[512]
    header += b"\0" * 32                               # id
    header += b"\0" * 1024                             # extra cmdline
    assert len(header) == 1632, len(header)
    out = pad(bytes(header)) + pad(payload)
    return out


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if len(args) < 2:
        print(__doc__)
        return 2
    src, dst = Path(args[0]), Path(args[1])
    payload = src.read_bytes()
    cmdline = STOCK_CMDLINE
    for f in flags:
        if f.startswith("--cmdline="):
            cmdline = f.split("=", 1)[1].encode()
    gzipped = "--gzip" in flags
    image = build(payload, cmdline, gzipped)
    dst.write_bytes(image)
    cmd_field = image[0x40:0x240].split(b"\0")[0]
    print(f"{src} ({len(payload):,} bytes) -> {dst} ({len(image):,} bytes)")
    print(f"  gzipped payload : {gzipped}")
    print(f"  kernel_size     : {struct.unpack_from('<I', image, 8)[0]:,}")
    print(f"  kernel_addr     : {struct.unpack_from('<I', image, 12)[0]:#x}")
    print(f"  page_size       : {struct.unpack_from('<I', image, 36)[0]}")
    print(f"  cmdline         : {cmd_field[:60]!r}...")
    return 0


if __name__ == "__main__":
    sys.exit(main())
