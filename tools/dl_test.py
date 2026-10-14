#!/usr/bin/env python3
"""First `download:` protocol test: arm a 256 KiB download, stream the
payload, expect OKAY.

The command write can sit undispatched (EP1 OUT lags one transfer on this
handoff), so the command is re-sent only while no reply has appeared.
Payload pattern: byte i = i & 0xFF, so the kernel log should show
dl_w0 = 0x03020100 and dl_wl = 0xFFFEFDFC for size 0x40000.
"""
import sys
import time

import usb.core
import usb.util

SIZE = 0x40000
payload = bytes(i & 0xFF for i in range(SIZE))

dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
if dev is None:
    print("device not found")
    sys.exit(1)
try:
    dev.set_configuration()
except Exception:
    pass
usb.util.claim_interface(dev, 0)

# drain stale bytes
quiet = 0
while quiet < 6:
    try:
        dev.read(0x81, 4096, timeout=300)
        quiet = 0
    except usb.core.USBError:
        quiet += 1
print("drained", flush=True)

cmd = f"download:{SIZE:08x}".encode()

pre = b""
for attempt in range(3):
    print(f"send download (attempt {attempt + 1})", flush=True)
    dev.write(0x01, cmd)
    deadline = time.time() + 2.5
    while time.time() < deadline:
        try:
            pre += bytes(dev.read(0x81, 4096, timeout=400))
        except usb.core.USBError:
            if b"DATA" in pre:
                break
    if b"DATA" in pre:
        break
print("pre:", pre[:64], flush=True)

t0 = time.time()
for off in range(0, SIZE, 512):
    dev.write(0x01, payload[off : off + 512], timeout=5000)
t1 = time.time()
print(f"payload sent in {t1 - t0:.2f}s", flush=True)

post = b""
deadline = time.time() + 20
while time.time() < deadline:
    try:
        post += bytes(dev.read(0x81, 4096, timeout=1000))
    except usb.core.USBError:
        if b"OKAY" in post:
            break
print("post:", post[:64], flush=True)
print("RESULT:", "OKAY" if b"OKAY" in post else "NO-OKAY", flush=True)
