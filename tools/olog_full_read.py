#!/usr/bin/env python3
"""Drain stale EP1 bytes, request `oem log full`, and stream the whole log.

Each streamed line is one transfer: "INFO<text>" (packet framed, no NUL).
Terminator: "OKAYdone". Every packet lands in /tmp/olog_stream.txt.
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
except Exception:
    pass
usb.util.claim_interface(dev, 0)

out = open("/tmp/olog_stream.txt", "w")

# 1) drain stale bytes (abandoned stream residue from earlier sessions)
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

# 2) request the full log. The core's EP1 OUT completion can lag one
# transfer (the same handoff quirk family as the loader's stale word), so
# send the command twice: the second write's boundary dispatches the first.
dev.write(0x01, b"oem log full")
time.sleep(0.5)
dev.write(0x01, b"oem log full")
t0 = time.time()
nlines = 0
done = False
while time.time() - t0 < 900:
    try:
        r = bytes(dev.read(0x81, 4096, timeout=1500))
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
print("streamed", nlines, "lines; done =", done, flush=True)
out.close()
