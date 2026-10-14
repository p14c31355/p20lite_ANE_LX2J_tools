#!/usr/bin/env python3
"""adbtest retry: send CNXN twice (the one-lag residue), read the reply."""
import struct
import time

import usb.core
import usb.util


def frame(command, arg0, arg1, payload=b""):
    cmd = int.from_bytes(command, "little")
    hdr = struct.pack(
        "<IIIIII", cmd, arg0, arg1, len(payload),
        sum(payload) % (2 ** 32), cmd ^ 0xFFFFFFFF,
    )
    return hdr + payload


dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
print("dev", dev is not None)
try:
    usb.util.claim_interface(dev, 0)
except Exception as e:
    print("claim:", e)

quiet = 0
while quiet < 3:
    try:
        r = bytes(dev.read(0x81, 65536, timeout=1200))
        quiet = 0 if r else quiet + 1
        if r:
            print("drain+", len(r), r[:40])
    except usb.core.USBError as e:
        quiet += 1
        if e.errno != 110:
            print("drainerr", e)

cnxn = frame(b"OPEN", 1, 0, b"shell:ver\x00")
for w in (1, 2):
    try:
        dev.write(0x01, cnxn, timeout=6000)
        print("wrote", w, len(cnxn))
    except usb.core.USBError as e:
        print("w", w, "err", e)
    time.sleep(0.4)

t0 = time.time()
got = bytearray()
while time.time() - t0 < 45:
    try:
        r = bytes(dev.read(0x81, 65536, timeout=2500))
        if r:
            got += r
            print("READ+", len(r), r[:80])
    except usb.core.USBError as e:
        if e.errno != 110:
            print("rerr", e)

if got:
    cmd, a0, a1, ln, ck, magic = struct.unpack("<IIIIII", got[:24])
    print("reply cmd:", cmd.to_bytes(4, "little"), "a0:", hex(a0), "a1:", hex(a1), "len:", ln)
    print("payload:", bytes(got[24 : 24 + ln]))
else:
    print("no reply")
