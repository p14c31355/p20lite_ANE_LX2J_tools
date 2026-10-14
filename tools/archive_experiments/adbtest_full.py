#!/usr/bin/env python3
"""Full ADB handshake: CNXN then OPEN(shell:ver), with the write-twice lag
tolerance. Prints every frame the device answers."""
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


def parse_frames(buf):
    frames = []
    off = 0
    while off + 24 <= len(buf):
        cmd, a0, a1, ln, ck, magic = struct.unpack("<IIIIII", buf[off : off + 24])
        name = cmd.to_bytes(4, "little").decode("ascii", "replace")
        payload = bytes(buf[off + 24 : off + 24 + ln])
        frames.append((name, a0, a1, payload))
        off += 24 + ln
    return frames


dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
print("dev", dev is not None)
try:
    usb.util.claim_interface(dev, 0)
except Exception as e:
    print("claim:", e)


def send(pkt, label, read_s=30):
    for w in (1, 2):
        try:
            dev.write(0x01, pkt, timeout=5000)
        except usb.core.USBError:
            pass
        time.sleep(0.3)
    t0 = time.time()
    got = bytearray()
    while time.time() - t0 < read_s:
        try:
            r = bytes(dev.read(0x81, 65536, timeout=2000))
            if r:
                got += r
        except usb.core.USBError as e:
            if e.errno != 110:
                pass
    print(f"--- {label}: {len(got)} bytes")
    for name, a0, a1, payload in parse_frames(got):
        print(f"    {name} a0={a0:#x} a1={a1:#x} payload={payload!r}")
    return got


time.sleep(0.5)
send(frame(b"CNXN", 0x01000001, 4096, b"host::adbtest\x00"), "CNXN")
send(frame(b"OPEN", 1, 0, b"shell:ver\x00"), "OPEN shell:ver")
