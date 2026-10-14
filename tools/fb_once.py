#!/usr/bin/env python3
"""Send one command ONCE (no sacrifice, no double-send) and read the reply.

Isolates the double-send interaction from the command's own handler: the
lag means a single send can sit undispatched, so the reply may not come -
that is itself the observation (device alive vs dead).
"""
import sys
import time

import usb.core
import usb.util

cmd = sys.argv[1].encode() if len(sys.argv) > 1 else b"getvar:version"

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
while quiet < 6:
    try:
        dev.read(0x81, 4096, timeout=300)
        quiet = 0
    except usb.core.USBError:
        quiet += 1
print("drained", flush=True)

dev.write(0x01, cmd)
print("sent once", flush=True)
buf = b""
deadline = time.time() + 10
while time.time() < deadline:
    try:
        buf += bytes(dev.read(0x81, 4096, timeout=700))
    except usb.core.USBError:
        if buf:
            break
print("reply:", buf[:96], flush=True)
