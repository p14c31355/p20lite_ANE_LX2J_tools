#!/usr/bin/env python3
"""Send a fastboot command twice (EP1 OUT dispatch can lag one transfer),
after draining any stale bytes. Used for reboot-bootloader without a combo.
"""
import sys
import time

import usb.core
import usb.util

cmd = sys.argv[1].encode() if len(sys.argv) > 1 else b"reboot-bootloader"

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

dev.write(0x01, cmd)
time.sleep(0.4)
dev.write(0x01, cmd)
time.sleep(1.0)
try:
    r = bytes(dev.read(0x81, 512, timeout=1000))
    print("reply:", r)
except usb.core.USBError as e:
    print("reply: none", e)
print("sent", cmd, flush=True)
