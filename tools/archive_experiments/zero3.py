#!/usr/bin/env python3
"""zero3.py - poll for the kernel (ANE fastboot) device, claim, send the magic
CNXN, read the piggyback. Handles EBUSY by retrying the claim."""
import struct
import sys
import time

import usb.core
import usb.util


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "rings_night/zero3.bin"
    deadline = time.time() + 70
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
                print(f"[{time.strftime('%H:%M:%S')}] KERNEL DEVICE")
                try:
                    if d.is_kernel_driver_active(0):
                        d.detach_kernel_driver(0)
                except Exception as e:
                    print("detach:", e)
                try:
                    usb.util.claim_interface(d, 0)
                    dev = d
                except Exception as e:
                    print("claim:", e)
                    time.sleep(0.5)
        time.sleep(0.2)
    if dev is None:
        print("timeout waiting for kernel device")
        sys.exit(1)
    cs = sum(b"host::adbtest\x00") & 0xFFFFFFFF
    pkt = (
        struct.pack("<IIIIII", 0x4E584E43, 0xC0DE0001, 4096, 14, cs, 0x4E584E43 ^ 0xFFFFFFFF)
        + b"host::adbtest\x00"
    )
    sent = False
    for _ in range(3):
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
    while time.time() - t0 < 12:
        try:
            x = bytes(dev.read(0x81, 65536, timeout=1000))
            if x:
                buf += x
                print("read", len(x))
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
