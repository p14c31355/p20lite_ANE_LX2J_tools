#!/usr/bin/env python3
"""adbtest: speak the ADB wire to the ANE kernel responder.

Builds the standard 24-byte little-endian ADB packets (the same framing the
kernel's adb_wire.rs implements) and runs the handshake by hand:

  CNXN -> expect CNXN reply with the device banner
  OPEN(shell:ver) -> expect OKAY + WRTE(text) + CLSE

Usage: adbtest.py [cmd ...]   (default: cnxn open)
"""
import struct
import sys
import time

import usb.core
import usb.util

VID, PID = 0x18D1, 0xD00D
EP_OUT, EP_IN = 0x01, 0x81


def frame(command: bytes, arg0: int, arg1: int, payload: bytes = b"") -> bytes:
    cmd = int.from_bytes(command, "little")
    hdr = struct.pack(
        "<IIIIII",
        cmd,
        arg0,
        arg1,
        len(payload),
        sum(payload) & 0xFFFFFFFF,
        cmd ^ 0xFFFFFFFF,
    )
    return hdr + payload


def decode(buf: bytes):
    if len(buf) < 24:
        return None, None, None, None
    cmd, a0, a1, ln, ck, magic = struct.unpack("<IIIIII", buf[:24])
    name = cmd.to_bytes(4, "little").decode("ascii", "replace")
    return name, a0, a1, buf[24 : 24 + ln]


def main(argv):
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        print("device not found")
        return 1
    try:
        usb.util.claim_interface(dev, 0)
    except Exception as e:
        print("claim:", e)

    # Drain stale bytes.
    quiet = 0
    while quiet < 4:
        try:
            r = bytes(dev.read(EP_IN, 65536, timeout=1200))
            quiet = 0 if r else quiet + 1
            if r:
                print("drain+", len(r))
        except usb.core.USBError as e:
            quiet += 1
            if e.errno != 110:
                print("drainerr", e)

    steps = argv[1:] or ["cnxn", "open"]

    def send(pkt, label):
        try:
            dev.write(EP_OUT, pkt, timeout=8000)
            print(f">> {label}: {len(pkt)} bytes")
        except usb.core.USBError as e:
            print(f">> {label}: write error {e}")
            return None
        t0 = time.time()
        while time.time() - t0 < 20:
            try:
                r = bytes(dev.read(EP_IN, 65536, timeout=2500))
            except usb.core.USBError as e:
                if e.errno != 110:
                    print("readerr", e)
                continue
            if r:
                return r
        print(f"<< {label}: no reply")
        return None

    for step in steps:
        if step == "cnxn":
            rep = send(frame(b"CNXN", 0x01000001, 4096, b"host::adbtest\x00"), "CNXN")
        elif step.startswith("open"):
            svc = step.split(":", 1)[1] if ":" in step else "shell:ver"
            rep = send(frame(b"OPEN", 1, 0, (svc + "\x00").encode()), f"OPEN({svc})")
        elif step == "clse":
            rep = send(frame(b"CLSE", 1, 1), "CLSE")
        else:
            print("unknown step", step)
            continue
        if rep is None:
            continue
        name, a0, a1, payload = decode(rep)
        print(f"<< {name} a0={a0:#x} a1={a1:#x} payload={payload!r}")
        if name == "cnxn" or name == "CNXN":
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
