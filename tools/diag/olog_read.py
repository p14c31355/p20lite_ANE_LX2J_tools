#!/usr/bin/env python3
"""Read the in-flight `oem log full` stream over EP1.

No commands are sent: fb_poll deactivates the stream on any command. The
kernel paces one INFO line per service pass while a reader drains, so this
just reads until OKAYdone (or quiet). Full capture to /tmp/olog_capture.bin.
"""
import sys
import time

import usb.core
import usb.util

dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
if dev is None:
    print("device not found")
    sys.exit(1)
try:
    dev.set_configuration()
except Exception:
    pass
usb.util.claim_interface(dev, 0)

buf = bytearray()
t0 = time.time()
quiet = 0
while time.time() - t0 < 150:
    try:
        r = dev.read(0x81, 4096, timeout=400)
        buf += bytes(r)
        quiet = 0
    except usb.core.USBError:
        quiet += 1
    if b"OKAYdone" in bytes(buf):
        break
    if quiet > 30 and len(buf) > 0:
        break

data = bytes(buf)
open("/tmp/olog_capture.bin", "wb").write(data)
print("captured", len(data), "bytes; done =", b"OKAYdone" in data)
txt = data.decode("latin1", errors="replace")
for line in txt.split("\x00"):
    line = line.strip()
    if line:
        print(line)
