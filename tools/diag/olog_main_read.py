#!/usr/bin/env python3
"""Drain stale EP1 bytes, request `oem log main`, stream the whole block.

The main durable text block (cap 0xE000) holds the sections the 7 KiB
fixed copy can no longer reach (usb / sd / emmc bring-up). Each streamed
line is one transfer: "INFO<text>". Terminator: "OKAYdone".
"""
import sys
import time

import usb.core
import usb.util

dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
if dev is None:
    print("device not found")
    sys.exit(1)
# The kernel re-arms EP1 only on SET_CONFIGURATION(1). A stale session (or a
# previous recover-dance leaving config 0) keeps EP1 dead, and a plain
# set_configuration() is a wire no-op when config 1 is already set. Drive the
# (0)->(1) transition explicitly, then wait long enough for the v113 pump
# (~24.5 s cadence) to service the re-arm before touching EP1.
try:
    dev.ctrl_transfer(0x00, 9, 0, 0, None, timeout=30000)
except Exception as e:
    print("cfg0:", e, flush=True)
time.sleep(0.5)
try:
    dev.ctrl_transfer(0x00, 9, 1, 0, None, timeout=60000)
except Exception as e:
    print("cfg1:", e, flush=True)
time.sleep(35)
usb.util.claim_interface(dev, 0)

out = open("/tmp/olog_main.txt", "w")

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

cmd = b"oem log main"
# The v113 syscall/IRQ pump services the responder about every 24.5 s after
# EL0 starts; a 5 s default wait NAK-times-out. Allow far longer.
dev.write(0x01, cmd, timeout=90000)
time.sleep(0.4)
dev.write(0x01, cmd, timeout=90000)
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
print("streamed", nlines, "lines; done =", done, flush=True)
out.close()
