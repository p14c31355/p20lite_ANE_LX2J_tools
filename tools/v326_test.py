#!/usr/bin/env python3
"""v326_test.py - after the device re-attaches, stage ONE CNXN early and
poll up to 9 minutes for the deferred reply (it arrives when the boot
thread reaches the wait loop = the desktop render completed)."""
import struct
import sys
import time

import usb.core
import usb.util


def frame(cmd, a0, a1, p=b""):
    cs = sum(p) & 0xFFFFFFFF
    return struct.pack("<IIIIII", cmd, a0, a1, len(p), cs, cmd ^ 0xFFFFFFFF) + p


def main():
    dev = None
    deadline = time.time() + 180
    while time.time() < deadline and dev is None:
        try:
            d = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
        except Exception:
            d = None
        if d is not None:
            try:
                prod = usb.util.get_string(d, d.iProduct)
            except Exception:
                prod = None
            if prod == "ANE fastboot":
                dev = d
                print(f"[{time.strftime('%H:%M:%S')}] kernel device")
                break
        time.sleep(0.3)
    if dev is None:
        print("timeout waiting for device")
        sys.exit(1)
    for _ in range(5):
        try:
            usb.util.claim_interface(dev, 0)
            break
        except Exception:
            time.sleep(0.3)
    pkt = frame(0x4E584E43, 0x01000001, 4096, b"host::adbtest\x00")
    dev.write(0x01, pkt, timeout=3000)
    print("CNXN staged at", time.strftime("%H:%M:%S"))
    buf = b""
    t0 = time.time()
    while time.time() - t0 < 540:
        try:
            x = bytes(dev.read(0x81, 65536, timeout=3000))
            if x:
                buf += x
                print(f"+{time.time()-t0:.0f}s read {len(buf)}")
                if len(buf) > 100:
                    break
        except Exception:
            pass
    print("total:", len(buf))
    if buf:
        open("rings_night/v326_deferred.bin", "wb").write(buf)


if __name__ == "__main__":
    main()
