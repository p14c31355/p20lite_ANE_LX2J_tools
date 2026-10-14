#!/usr/bin/env python3
"""Decode `oem dump` output slices back into the raw ring bytes and print the
readable text. Each sector line is `em: dd=<16 hex>` = two u32 words packed
big-endian into one u64, i.e. the sector's 8 raw bytes in order."""
import re
import sys


def decode_slice(path: str) -> bytes:
    raw = bytearray()
    with open(path, "r", errors="replace") as f:
        for line in f:
            m = re.search(r"em: dd=([0-9a-fA-F]{16})", line)
            if not m:
                continue
            v = int(m.group(1), 16)
            raw += v.to_bytes(8, "big")
    return bytes(raw)


def main() -> None:
    for path in sys.argv[1:]:
        data = decode_slice(path)
        print(f"===== {path}: {len(data)} bytes =====")
        # The ring is plain ASCII text with NUL padding; show printable runs.
        text = data.decode("latin-1")
        # Split on NULs to show the segments, but keep newlines intact.
        segments = [seg for seg in text.split("\x00") if seg.strip()]
        for seg in segments:
            print(seg, end="")
        print()


if __name__ == "__main__":
    main()
