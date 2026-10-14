#!/usr/bin/env python3
"""Send extra padding to complete an armed download, then read the OKAY."""
import time

import usb.core
import usb.util

MORE = 10 << 20

dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
assert dev is not None, "device not found"
try:
    dev.set_configuration()
except Exception:
    pass
usb.util.claim_interface(dev, 0)

chunk = bytes(512)
t0 = time.time()
sent = 0
while sent < MORE:
    n = min(512, MORE - sent)
    dev.write(0x01, chunk[:n], timeout=5000)
    sent += n
print(f"sent +{sent} bytes in {time.time() - t0:.1f}s", flush=True)

buf = b""
quiet = 0
deadline = time.time() + 25
while time.time() < deadline and quiet < 2:
    try:
        buf += bytes(dev.read(0x81, 4096, timeout=700))
        quiet = 0
    except usb.core.USBError:
        quiet += 1
print("reply:", buf[:64], flush=True)
