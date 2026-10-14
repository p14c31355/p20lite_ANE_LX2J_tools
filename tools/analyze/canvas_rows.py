#!/usr/bin/env python3
"""canvas_rows.py - read a few canvas rows via oem xfer to check whether the
desktop rendered. The canvas is 1080x2340 BGRA at 0x31000000. Reading full
rows is slow (~110 B/s); read SMALL slivers: the first 256 bytes of a few
rows near the desktop's known render areas, plus the FB: strip rows."""
import subprocess
import sys
import time

UV = "/home/placeless/.hermes/bin/uv"


def xfer(addr, length, out):
    return subprocess.run(
        [UV, "run", "--with", "pyusb", "--no-project", "python3",
         "fb_xfer.py", "r", addr, length, out],
        capture_output=True, text=True, cwd="/home/placeless/dev/p20-root",
    )


def main():
    # 1. canvas start (0x31000000) 512 bytes: the desktop's top-left corner.
    #    The ANE text strip starts at DIAG_Y 446 => row byte offset
    #    446*1080*4 = 0x1C7C00. Desktop windows render below/around.
    spots = [
        ("canvas_top", 0x31000000, 512),
        ("diag_row", 0x31000000 + 446 * 1080 * 4, 512),
    ]
    for name, addr, ln in spots:
        out = f"/tmp/canvas_{name}.bin"
        r = xfer(hex(addr), hex(ln), out)
        ok = "OKAY" in (r.stdout + r.stderr)
        print(name, "ok" if ok else "fail", r.stdout[-60:], r.stderr[-60:])


if __name__ == "__main__":
    main()
