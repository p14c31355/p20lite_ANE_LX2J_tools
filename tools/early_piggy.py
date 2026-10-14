#!/usr/bin/env python3
"""early_piggy.py - race the earliest possible CNXN after enumeration.
Poll find+string at 0.1 s, claim with retries, send ONE magic CNXN (collect +
reset). For reading WHY a boot dies before/at enumeration."""
import struct
import sys
import time

import usb.core
import usb.util


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "rings_night/early.bin"
    deadline = time.time() + 90
    dev = None
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
        time.sleep(0.1)
    if dev is None:
        print("timeout")
        sys.exit(1)
    try:
        if dev.is_kernel_driver_active(0):
            dev.detach_kernel_driver(0)
    except Exception:
        pass
    claimed = False
    for _ in range(20):
        try:
            usb.util.claim_interface(dev, 0)
            claimed = True
            break
        except Exception as e:
            print("claim retry:", e)
            time.sleep(0.2)
    if not claimed:
        sys.exit(1)
    cs = sum(b"host::adbtest\x00") & 0xFFFFFFFF
    pkt = struct.pack(
        "<IIIIII", 0x4E584E43, 0xC0DE0001, 4096, 14, cs, 0x4E584E43 ^ 0xFFFFFFFF
    ) + b"host::adbtest\x00"
    sent = False
    for _ in range(3):
        try:
            dev.write(0x01, pkt, timeout=3000)
            sent = True
            print("magic CNXN sent")
            break
        except Exception as e:
            print("write:", e)
            time.sleep(0.2)
    buf = b""
    t0 = time.time()
    while time.time() - t0 < 10:
        try:
            x = bytes(dev.read(0x81, 65536, timeout=1000))
            if x:
                buf += x
                print("read", len(buf))
        except Exception:
            pass
    print("total:", len(buf))
    if buf:
        open(out, "wb").write(buf)


if __name__ == "__main__":
    main()
