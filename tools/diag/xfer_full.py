#!/usr/bin/env python3
"""xfer_full.py - after ONE getvar conversation (no magic), pull the FULL
32 KiB durable ring via `oem xfer r 348d0000 8000`. The v307 latch keeps the
boot alive for ~an hour, so this can take its time."""
import sys
import time

import usb.core
import usb.util


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "rings_night/v307_full.bin"
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
        print("timeout waiting for kernel")
        sys.exit(1)
    try:
        if dev.is_kernel_driver_active(0):
            dev.detach_kernel_driver(0)
    except Exception:
        pass
    claimed = False
    for _ in range(10):
        try:
            usb.util.claim_interface(dev, 0)
            claimed = True
            break
        except Exception as e:
            print("claim retry:", e)
            time.sleep(0.5)
    if not claimed:
        sys.exit(1)
    # 1. the latch-opening conversation: one getvar, no magic.
    try:
        dev.write(0x01, b"getvar:product\x00\x00", timeout=3000)
        print("getvar sent (latch opens)")
    except Exception as e:
        print("getvar write:", e)
        sys.exit(1)
    buf = b""
    t0 = time.time()
    while time.time() - t0 < 5:
        try:
            x = bytes(dev.read(0x81, 512, timeout=1000))
            if x:
                buf += x
        except Exception:
            pass
    print("getvar reply:", buf[:40])
    # 2. drain stale, then `oem xfer r 348d0000 8000` TWICE (one-behind law).
    time.sleep(1)
    try:
        dev.write(0x01, b"\x00" * 64, timeout=2000)
    except Exception:
        pass
    for attempt in range(2):
        try:
            dev.write(0x01, b"oem xfer r 348d0000 8000", timeout=3000)
            print(f"xfer cmd sent (attempt {attempt + 1})")
        except Exception as e:
            print("xfer write:", e)
    # 3. read the OKAY header + raw stream.
    buf = b""
    t0 = time.time()
    while time.time() - t0 < 240:
        try:
            x = bytes(dev.read(0x81, 16384, timeout=1500))
            if x:
                buf += x
                print(f"read {len(buf)} total")
                if b"OKAY" in buf[:32] and len(buf) > 32768:
                    break
        except Exception:
            pass
    print("total:", len(buf))
    if buf:
        open(out, "wb").write(buf)


if __name__ == "__main__":
    main()
