#!/usr/bin/env python3
"""Send `oem udmount` (the on-demand userdata mount) and wait patiently for
the OKAYudm reply. The mount is slow (48 KB/s sector reads); a crash drops
the device and the safety catcher + watchdog handle recovery.

The kernel re-inits EP1 only on SET_CONFIGURATION(1), so any fresh pyusb
session must drive the SET_CONFIGURATION(0)->(1) dance first (or the EP1
OUT write can NAK forever). fb_recover_ep1.py proved this."""
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

# Re-init EP1 in the kernel: SET_CONFIGURATION(0) -> (1).
for val in (0, 1):
    try:
        dev.ctrl_transfer(0x00, 9, val, 0, None, timeout=3000)
        print(f"SET_CONFIGURATION {val} ok", flush=True)
    except Exception as e:
        print(f"SET_CONFIGURATION {val} failed: {e}", flush=True)
    time.sleep(1.0)

quiet = 0
while quiet < 4:
    try:
        dev.read(0x81, 4096, timeout=250)
        quiet = 0
    except usb.core.USBError:
        quiet += 1

cmd = b"oem udmount"
dev.write(0x01, cmd)
time.sleep(0.4)
dev.write(0x01, cmd)
t0 = time.time()
while time.time() - t0 < 900:
    try:
        r = bytes(dev.read(0x81, 4096, timeout=3000))
    except usb.core.USBError as e:
        print(f"USBError at t={time.time()-t0:.0f}s: {e}", flush=True)
        continue
    if r:
        print(f"t={time.time()-t0:.0f}s reply: {r[:120]!r}", flush=True)
        if b"OKAYudm" in r:
            break
else:
    print("timeout waiting for OKAYudm")
print(f"done after {time.time()-t0:.0f}s")
