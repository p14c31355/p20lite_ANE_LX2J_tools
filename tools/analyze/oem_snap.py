#!/usr/bin/env python3
"""Auto screenshot of the ANE kernel canvas via `oem xfer r`.

The kernel's diag canvas lives at 0x31000000 (1080x2340x4, BGRA byte order
in memory). The on-screen text area starts at y=686 (row 0) with a 24 px
line pitch. This tool pulls the text region in ~1.7 MB chunks (the kernel's
xfer cap is 4 MB per call) and stitches them into a plain PPM (P6) image -
no library dependencies, viewable anywhere.

Usage: oem_snap.py <out.ppm>

Uses the same transport dance as fb_xfer.py (deep drain, write-once,
OKAY-header scan, EIO recovery via SET_CONFIGURATION(0)->(1)).
"""
import sys
import time

import usb.core
import usb.util

CANVAS = 0x31000000
W = 1080
ROW_BYTES = W * 4           # 4320 bytes per canvas row
Y0 = 1046                   # y of text row 15 (instruments start)
Y1 = 2126                   # y end (row 60; the ledger + tail rows)
CHUNK_ROWS = 45             # ~194 KB per xfer: fits the slow tick-paced stream
WINDOW = float(__import__("os").environ.get("SNAP_WINDOW", "300"))


def connect():
    for _ in range(60):
        dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
        if dev is not None:
            try:
                dev.set_configuration()
            except Exception:
                pass
            time.sleep(0.3)
            return dev
        time.sleep(0.5)
    return None


def do_dance(dev):
    try:
        dev.ctrl_transfer(0x00, 9, 0, 0, None, timeout=10000)
    except Exception:
        pass
    time.sleep(0.4)
    try:
        dev.ctrl_transfer(0x00, 9, 1, 0, None, timeout=30000)
    except Exception:
        pass
    time.sleep(4)
    try:
        usb.util.claim_interface(dev, 0)
    except Exception:
        pass


def drain(dev):
    quiet = 0
    t0 = time.time()
    while quiet < 8 and time.time() - t0 < 30:
        try:
            r = bytes(dev.read(0x81, 65536, timeout=1200))
            quiet = 0 if r else quiet + 1
        except usb.core.USBError as e:
            if e.errno == 110:
                quiet += 1
            else:
                quiet += 1


def xfer(dev, addr, ln):
    """One `oem xfer r` call: returns exactly ln bytes or None."""
    cmd = f"oem xfer r {addr:x} {ln:x}".encode()
    try:
        dev.write(0x01, cmd, timeout=8000)
    except usb.core.USBError as e:
        print("write:", e, flush=True)
        return None
    got = bytearray()
    header_len = None
    payload_start = None
    eio = False
    t0 = time.time()
    while time.time() - t0 < WINDOW:
        try:
            r = bytes(dev.read(0x81, 65536, timeout=3000))
        except usb.core.USBError as e:
            if e.errno != 110 and not eio:
                print("readerr:", e, flush=True)
                eio = True
            r = b""
        if r:
            got += r
            if payload_start is None:
                i = got.find(b"OKAY")
                if i >= 0 and len(got) >= i + 20:
                    header_len = int(bytes(got[i + 4 : i + 20]), 16)
                    payload_start = i + 20
                    print("OKAY len:", header_len, flush=True)
            if payload_start is not None and len(got) - payload_start >= header_len:
                return bytes(got[payload_start : payload_start + header_len])
        elif eio:
            print("EIO - dancing once", flush=True)
            do_dance(dev)
            return None
    print("timeout; got", len(got), "bytes (hdr:", header_len, ")", flush=True)
    return None


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    out = sys.argv[1]
    dev = connect()
    if dev is None:
        print("no device")
        sys.exit(2)
    try:
        usb.util.claim_interface(dev, 0)
    except Exception as e:
        print("claim:", e)
    drain(dev)

    rows = (Y1 - Y0) // 1
    data = bytearray()
    y = Y0
    while y < Y1:
        n_rows = min(CHUNK_ROWS, Y1 - y)
        ln = n_rows * ROW_BYTES
        addr = CANVAS + y * ROW_BYTES
        print(f"pull y={y} rows={n_rows} len=0x{ln:x}", flush=True)
        part = xfer(dev, addr, ln)
        if part is None or len(part) != ln:
            print("part failed at y=", y, "got", 0 if part is None else len(part))
            sys.exit(3)
        data += part
        y += n_rows

    h = len(data) // ROW_BYTES
    # Canvas pixels are 0xAARRGGBB in LE: bytes in memory are B,G,R,A.
    # Write a PPM (P6, RGB) dropping alpha: take bytes 0,1,2 of each pixel.
    out_bytes = bytearray(W * h * 3)
    src = memoryview(data)
    for px in range(W * h):
        b = px * 4
        d = px * 3
        out_bytes[d] = src[b + 2]      # R
        out_bytes[d + 1] = src[b + 1]  # G
        out_bytes[d + 2] = src[b]      # B
    with open(out, "wb") as f:
        f.write(b"P6\n%d %d\n255\n" % (W, h))
        f.write(out_bytes)
    print(f"wrote {out}: {W}x{h}")


if __name__ == "__main__":
    main()
