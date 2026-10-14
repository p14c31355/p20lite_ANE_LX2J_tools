#!/usr/bin/env python3
"""E1 v3: locate and use the raw bulk path in pyusb's backend chain."""
import sys
import usb.core

cmd = (" ".join(sys.argv[1:]) or "oem xfer r 348d0000 2000").encode()

dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
if dev is None:
    sys.exit("no device")

try:
    dev.ctrl_transfer(0x00, 0x09, 1, 0, timeout=2000)
    print("cfg ok")
except Exception as e:
    print("cfg err:", e)

rm = dev._ctx
dh = rm.handle
bh = getattr(dh, "handle", None)
print("dh:", type(dh).__name__, [a for a in dir(dh) if not a.startswith("__")])
if bh is not None:
    print("bh:", type(bh).__name__, [a for a in dir(bh) if not a.startswith("__")])


def try_call(obj, name, *args, **kw):
    fn = getattr(obj, name, None)
    if fn is None:
        return None
    try:
        v = fn(*args, **kw)
        print(f"{name}@{type(obj).__name__}: ok ->", repr(v)[:100])
        return v
    except Exception as e:
        print(f"{name}@{type(obj).__name__} err:", type(e).__name__, e)
        return None


for obj in (dh, bh):
    if obj is None:
        continue
    try_call(obj, "claim_interface", 0)

for obj in (dh, bh):
    if obj is None:
        continue
    try_call(obj, "bulk_write", 0x01, cmd, timeout=3000)
    try_call(obj, "bulk", 0x01, cmd, timeout=3000)

for obj in (dh, bh):
    if obj is None:
        continue
    d = try_call(obj, "bulk_read", 0x81, 512, timeout=4000)
    if d is None:
        d = try_call(obj, "bulk", 0x81, 512, timeout=4000)
    if d:
        print("READ:", len(d), repr(bytes(d[:96])))
