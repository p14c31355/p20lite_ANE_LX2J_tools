#!/usr/bin/env python3
"""Timed `oem log` stream probe for the ANE in-kernel fastboot.

Writes "oem log" and reads the response stream with per-line timestamps so
the slowness can be attributed: if lines arrive fast here (pyusb) but slow
through the fastboot client, the client is the bottleneck; if they are slow
here too, the device side is.

Usage: uv run --no-project --with pyusb python3 olog_timed.py [seconds]
"""
import sys
import time

import usb.core
import usb.util

VID, PID = 0x18D1, 0xD00D
SECONDS = int(sys.argv[1]) if len(sys.argv) > 1 else 60

dev = usb.core.find(idVendor=VID, idProduct=PID)
if dev is None:
    print("device not found")
    sys.exit(1)

for cfg in dev:
    for iface in cfg:
        try:
            if dev.is_kernel_driver_active(iface.bInterfaceNumber):
                dev.detach_kernel_driver(iface.bInterfaceNumber)
        except Exception:
            pass
try:
    dev.set_configuration()
except Exception:
    pass

try:
    usb.util.claim_interface(dev, 0)
except Exception as e:
    print("claim:", e)

EP_OUT = 0x01
EP_IN = 0x81


def read_once(timeout_ms=200):
    try:
        return bytes(dev.read(EP_IN, 4096, timeout=timeout_ms))
    except Exception:
        return None


# Drain leftovers (up to a second of silence).
while True:
    r = read_once(300)
    if not r:
        break

t0 = time.monotonic()
dev.write(EP_OUT, b"oem log")
print("sent oem log at t=0")

n = 0
last = t0
while time.monotonic() - t0 < SECONDS:
    r = read_once(500)
    now = time.monotonic() - t0
    if r is None:
        continue
    n += 1
    print("t=%6.2f  dt=%5.2f  %3dB  %r" % (now, now - last, len(r), r[:44]))
    last = now
    if b"OKAY" in r and n > 2 and (time.monotonic() - t0) - last > 2:
        pass

print("total: %d transfers in %.1fs" % (n, time.monotonic() - t0))
