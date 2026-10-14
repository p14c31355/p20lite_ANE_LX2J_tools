#!/usr/bin/env python3
"""Unstick a download that was armed but never fed: stream exactly the
expected byte count of padding so DL_REMAIN reaches 0 and the receiver
replies OKAY and resets. (The v91 flash attempt armed download: but the
client bailed before sending the payload.)
"""
import sys
import time

import usb.core
import usb.util

SIZE = 11429888  # the v91 artifact's image size (the client's download size)

dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
if dev is None:
    print("device not found")
    sys.exit(1)
try:
    dev.set_configuration()
except Exception:
    pass
usb.util.claim_interface(dev, 0)

quiet = 0
while quiet < 4:
    try:
        dev.read(0x81, 4096, timeout=300)
        quiet = 0
    except usb.core.USBError:
        quiet += 1
print("drained", flush=True)

chunk = bytes(512)
t0 = time.time()
sent = 0
while sent < SIZE:
    n = min(512, SIZE - sent)
    dev.write(0x01, chunk[:n], timeout=5000)
    sent += n
t1 = time.time()
print(f"sent {sent} bytes in {t1 - t0:.1f}s", flush=True)

buf = b""
deadline = time.time() + 20
quiet = 0
while time.time() < deadline and quiet < 2:
    try:
        buf += bytes(dev.read(0x81, 4096, timeout=700))
        quiet = 0
    except usb.core.USBError:
        quiet += 1
print("reply:", buf[:64], flush=True)
