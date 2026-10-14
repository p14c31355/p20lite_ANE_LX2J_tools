#!/usr/bin/env python3
"""E1 v4: raw-endpoint session via python-libusb1 (no descriptor parsing).

Usage: raw_libusb.py <command>
"""
import sys
import usb1

cmd = (" ".join(sys.argv[1:]) or "oem xfer r 348d0000 2000").encode()

ctx = usb1.USBContext()
dev = ctx.getByVendorIDAndProductID(0x18D1, 0xD00D)
if dev is None:
    sys.exit("no device")
print("dev:", dev)

h = dev.open()
print("opened")

try:
    h.setConfiguration(1)
    print("cfg ok")
except Exception as e:
    print("cfg err:", type(e).__name__, e)

try:
    h.claimInterface(0)
    print("claim ok")
except Exception as e:
    print("claim err:", type(e).__name__, e)

try:
    n = h.bulkWrite(0x01, cmd, timeout=3000)
    print("write:", n, "bytes")
except Exception as e:
    print("write err:", type(e).__name__, e)
    sys.exit(1)

try:
    d = h.bulkRead(0x81, 512, timeout=4000)
    print("read:", len(d), repr(bytes(d[:96])))
except Exception as e:
    print("read err:", type(e).__name__, e)
