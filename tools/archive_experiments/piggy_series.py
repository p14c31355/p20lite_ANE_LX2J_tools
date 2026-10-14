#!/usr/bin/env python3
"""piggy_series.py - the boot is long-lived (v307 latch). Take a series of
CNXN piggybacks WITHOUT the magic reset (arg0 = normal version), each giving
the newest 2 KB of the ring. A series reconstructs the narrative."""
import struct
import sys
import time

import usb.core
import usb.util

CNXN = 0x4E584E43


def frame(cmd, a0, a1, payload=b""):
    cs = sum(payload) & 0xFFFFFFFF
    return struct.pack("<IIIIII", cmd, a0, a1, len(payload), cs, cmd ^ 0xFFFFFFFF) + payload


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 6
    prefix = sys.argv[2] if len(sys.argv) > 2 else "rings_night/series"
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
    for i in range(count):
        # normal CNXN (no magic) -> piggyback reply, boot stays alive.
        pkt = frame(CNXN, 0x01000001, 4096, b"host::adbtest\x00")
        sent = False
        for _ in range(2):
            try:
                dev.write(0x01, pkt, timeout=3000)
                sent = True
                break
            except Exception as e:
                print(f"#{i} write:", e)
                time.sleep(0.4)
        buf = b""
        t0 = time.time()
        while time.time() - t0 < 8:
            try:
                x = bytes(dev.read(0x81, 65536, timeout=1000))
                if x:
                    buf += x
            except Exception:
                pass
        fn = f"{prefix}_{i}.bin"
        if buf:
            open(fn, "wb").write(buf)
        print(f"#{i}: sent={sent} bytes={len(buf)} -> {fn}")
        time.sleep(3)


if __name__ == "__main__":
    main()
