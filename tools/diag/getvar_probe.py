#!/usr/bin/env python3
"""getvar_probe.py - send ONE fastboot getvar (no magic reset) to a fresh
kernel enumeration, then exit. Leaves the boot alive so the latch's effect
on lifetime is measurable from the journal."""
import sys
import time

import usb.core
import usb.util


def main():
    deadline = time.time() + 60
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
        time.sleep(0.2)
    if dev is None:
        print("timeout")
        sys.exit(1)
    try:
        if dev.is_kernel_driver_active(0):
            dev.detach_kernel_driver(0)
    except Exception:
        pass
    for _ in range(10):
        try:
            usb.util.claim_interface(dev, 0)
            break
        except Exception as e:
            print("claim retry:", e)
            time.sleep(0.5)
    else:
        print("claim failed")
        sys.exit(1)
    cmd = b"getvar:product\x00\x00"
    try:
        dev.write(0x01, cmd, timeout=3000)
        print("getvar sent")
    except Exception as e:
        print("write:", e)
        sys.exit(1)
    buf = b""
    t0 = time.time()
    while time.time() - t0 < 6:
        try:
            x = bytes(dev.read(0x81, 512, timeout=1000))
            if x:
                buf += x
        except Exception:
            pass
    print("reply:", buf[:80])
    # NO reset, NO magic - leave the boot running.


if __name__ == "__main__":
    main()
