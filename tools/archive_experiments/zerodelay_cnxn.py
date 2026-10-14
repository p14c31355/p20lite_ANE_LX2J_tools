#!/usr/bin/env python3
"""zerodelay_cnxn.py - find the KERNEL (ANE fastboot) device, claim, send the
magic CNXN once, read the piggyback reply. No SET_CONFIGURATION dance."""
import struct
import sys
import time

import usb.core
import usb.util


def frame(cmd, a0, a1, payload=b""):
    cs = sum(payload) & 0xFFFFFFFF
    return struct.pack("<IIIIII", cmd, a0, a1, len(payload), cs, cmd ^ 0xFFFFFFFF) + payload


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "rings_night/zerodelay.bin"
    dev = None
    for _ in range(150):  # ~30 s at 0.2 s
        try:
            d = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
        except Exception:
            d = None
        if d is not None:
            try:
                prod = usb.util.get_string(d, d.iProduct)
            except Exception:
                prod = "?"
            if prod == "ANE fastboot":
                dev = d
                break
        time.sleep(0.2)
    if dev is None:
        print("no kernel device")
        sys.exit(1)
    print("kernel device found")
    try:
        if dev.is_kernel_driver_active(0):
            dev.detach_kernel_driver(0)
    except Exception:
        pass
    usb.util.claim_interface(dev, 0)
    pkt = frame(0x4E584E43, 0xC0DE0001, 4096, b"host::adbtest\x00")
    sent = False
    for attempt in range(2):
        try:
            dev.write(0x01, pkt, timeout=3000)
            sent = True
            print("write ok")
            break
        except Exception as e:
            print("write:", e)
            time.sleep(0.3)
    buf = b""
    t0 = time.time()
    while time.time() - t0 < 15:
        try:
            d = bytes(dev.read(0x81, 65536, timeout=1000))
            if d:
                buf += d
                print("read", len(d))
        except Exception:
            pass
    print("total:", len(buf))
    if buf:
        open(out, "wb").write(buf)
        open("/tmp/adb_raw_last.bin", "wb").write(buf)
    if not sent or not buf:
        sys.exit(1)


if __name__ == "__main__":
    main()
