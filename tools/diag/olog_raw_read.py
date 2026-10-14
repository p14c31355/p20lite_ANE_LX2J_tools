#!/usr/bin/env python3
"""Drain stale EP1 bytes, request `oem log raw`, stream the WHOLE 0xE000
ring (both sides of `raw` - the pre-wrap content the `main` stream cannot
reach). Terminator: "OKAYdone"."""
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

out = open("/tmp/olog_raw.txt", "w")

quiet = 0
drained = 0
while quiet < 6:
    try:
        r = dev.read(0x81, 4096, timeout=300)
        drained += len(r)
        quiet = 0
    except usb.core.USBError:
        quiet += 1
print("drained", drained, "bytes", flush=True)
out.write(f"# drained {drained}\n")

cmd = b"oem log raw"
dev.write(0x01, cmd)
time.sleep(0.4)
dev.write(0x01, cmd)
t0 = time.time()
nlines = 0
done = False
while time.time() - t0 < 1500:
    try:
        r = bytes(dev.read(0x81, 4096, timeout=2000))
    except usb.core.USBError:
        continue
    if not r:
        continue
    txt = r.decode("latin1", errors="replace")
    if txt.startswith("INFO"):
        txt = txt[4:]
    out.write(txt.rstrip("\x00") + "\n")
    out.flush()
    nlines += 1
    if "OKAYdone" in txt:
        done = True
        break
print("lines", nlines, "done", done, flush=True)
sys.exit(0 if done else 2)
