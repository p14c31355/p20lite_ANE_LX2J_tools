#!/usr/bin/env python3
"""Recover a wedged kernel EP1 OUT: drive the control path.

The kernel's setup handler re-inits EP1 on every SET_CONFIGURATION(1)
(ane_usb_dev.rs, the `if wvalue != 0` branch), and the control endpoint
has stayed healthy through every EP1 problem so far. SET_CONFIGURATION(0)
-> (1) is the USB-legit re-init dance; give the kernel a beat between.
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
except Exception as e:
    print("set_configuration:", e)

for val in (0, 1):
    try:
        dev.ctrl_transfer(0x00, 9, val, 0, None, timeout=3000)  # SET_CONFIGURATION
        print("SET_CONFIGURATION", val, "ok")
    except Exception as e:
        print("SET_CONFIGURATION", val, "failed:", e)
    time.sleep(1.0)

# Then try a single EP1 OUT write and read whatever comes back.
try:
    dev.write(0x01, b"getvar:version", timeout=8000)
    print("EP1 write ok")
    try:
        r = dev.read(0x81, 4096, timeout=8000)
        print("EP1 read:", bytes(r))
    except Exception as e:
        print("EP1 read failed:", e)
except Exception as e:
    print("EP1 write failed:", e)
