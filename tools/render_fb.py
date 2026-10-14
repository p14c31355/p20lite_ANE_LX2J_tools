#!/usr/bin/env python3
"""Render a raw ANE framebuffer region to PNG (no dependencies).

Input: a raw dump of the canvas (0x31000000, 1080 x 2340, 32 bpp).
Usage: render_fb.py <raw.bin> <out.png> [width] [height] [bgra|rgba]

The canvas pixels are little-endian u32. The kernel draws FG=0xFFFFFF00
(a yellow) - if the output looks blue, flip the channel mode.
"""
import struct
import sys
import zlib


def png_from_rgba(width, height, rgba):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter: none
        raw += rgba[y * stride:(y + 1) * stride]
    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", ihdr)
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    out += chunk(b"IEND", b"")
    return out


path = sys.argv[1]
outp = sys.argv[2]
width = int(sys.argv[3]) if len(sys.argv) > 3 else 1080
height = int(sys.argv[4]) if len(sys.argv) > 4 else 2340
mode = sys.argv[5] if len(sys.argv) > 5 else "bgra"

data = open(path, "rb").read()

# A partial dump: derive the height from the length.
rows = len(data) // (width * 4)
if rows == 0:
    print(f"too small: {len(data)} bytes for width {width}")
    sys.exit(1)
height = min(height, rows)
data = data[: height * width * 4]

rgba = bytearray(height * width * 4)
for i in range(0, len(data), 4):
    b0, b1, b2, b3 = data[i], data[i + 1], data[i + 2], data[i + 3]
    if mode == "bgra":
        r, g, b = b2, b1, b0
        a = 255
    else:  # rgba
        r, g, b, a = b0, b1, b2, b3 if b3 else 255
    rgba[i] = r
    rgba[i + 1] = g
    rgba[i + 2] = b
    rgba[i + 3] = a

open(outp, "wb").write(png_from_rgba(width, height, bytes(rgba)))
print(f"{outp}: {width}x{height} ({mode}) from {len(data)} bytes")
