#!/usr/bin/env python3
"""Send one fastboot getvar command (with the standard sacrifice) and print
the reply. Used to reproduce the partition-size:kernel crash in isolation.
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

# sacrifice: release the EP1-OUT lag one transfer early, then drain the
# TWO replies its double dispatch produces (a leftover reply would shift
# the next session's command/response pairing).
dev.write(0x01, b"getvar:version")
time.sleep(0.4)
dev.write(0x01, b"getvar:version")
time.sleep(0.6)
quiet = 0
while quiet < 2:
    try:
        dev.read(0x81, 4096, timeout=400)
        quiet = 0
    except usb.core.USBError:
        quiet += 1
print("sacrificed", flush=True)

# the real command, sent twice (lag release)
dev.write(0x01, cmd)
time.sleep(0.4)
dev.write(0x01, cmd)
time.sleep(0.8)
buf = b""
deadline = time.time() + 30
quiet = 0
while time.time() < deadline and quiet < 2:
    try:
        buf += bytes(dev.read(0x81, 4096, timeout=700))
        quiet = 0
    except usb.core.USBError:
        quiet += 1
print("reply:", buf[:96], flush=True)
print("RESULT:", buf[:96], flush=True)
