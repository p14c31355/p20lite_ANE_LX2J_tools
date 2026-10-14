#!/usr/bin/env python3
"""Probe the ANE responder: one command write, short read. Exit 0 on any
reply (the endpoint is live), 1 on silence (wedged/frozen world), 2 on no
device, 3 on write failure."""
import sys
import time

import usb.core
import usb.util

dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
if dev is None:
    sys.exit(2)
try:
    usb.util.claim_interface(dev, 0)
except Exception:
    pass
for attempt in (1, 2):
    try:
        dev.write(0x01, b"getvar:version", timeout=5000)
    except usb.core.USBError:
        if attempt == 2:
            sys.exit(3)
    time.sleep(0.3)
t0 = time.time()
while time.time() - t0 < 12:
    try:
        r = bytes(dev.read(0x81, 65536, timeout=1500))
        if r:
            print("reply", len(r), r[:24])
            sys.exit(0)
    except usb.core.USBError as e:
        if e.errno != 110:
            time.sleep(0.2)
sys.exit(1)
