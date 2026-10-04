#!/usr/bin/env python3
"""Unsparse an Android sparse image (version 1.0) to a raw image.

The UPDATE.APP partitions arrive as Android sparse images; debugfs needs the
raw ext4 that is inside. Format (little-endian):
  header: magic 0xED26FF3A, major, minor, hdr_size(28), chunk_hdr_size(12),
          blk_size(4096), total_blks, total_chunks, crc
  chunk:  type(0xCAC1 raw, 0xCAC2 fill, 0xCAC3 dontcare, 0xCAC4 crc32),
          reserved, chunk_blocks, total_size
Every 4096-byte output block covered by a chunk writes once.

Usage: unsparse.py <in.sparse.img> <out.raw.img>
"""
import struct
import sys

MAGIC = 0xED26FF3A


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, "rb") as f:
        hdr = f.read(28)
        magic, _maj, _min, hsz, chsz, blk, total_blks, total_chunks, _crc = \
            struct.unpack("<IHHHHIIII", hdr)
        assert magic == MAGIC, f"not a sparse image (magic {magic:#x})"
        written = 0
        chunks = 0
        with open(dst, "wb") as o:
            while chunks < total_chunks:
                ch = f.read(chsz)
                ctype, _res, cblks, tsize = struct.unpack("<HHII", ch)
                nbytes = cblks * blk
                if ctype == 0xCAC1:          # raw
                    o.write(f.read(nbytes))
                elif ctype == 0xCAC2:        # fill
                    fill = f.read(4)
                    o.write(fill * cblks * (blk // len(fill)))
                elif ctype == 0xCAC3:        # dontcare
                    o.write(b"\x00" * nbytes)
                elif ctype == 0xCAC4:        # crc32 chunk: no output
                    f.read(tsize - chsz)
                    chunks += 1
                    continue
                else:
                    raise SystemExit(f"unknown chunk type {ctype:#x}")
                written += nbytes
                chunks += 1
        print(f"wrote {dst}: {written:,} bytes ({total_blks} blocks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
