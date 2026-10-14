#!/usr/bin/env python3
"""Fast raw transfer from the ANE via `oem xfer`.

Usage: fb_xfer.py r <addr-hex> <len-hex> <out-file>      (raw RAM bytes)
       fb_xfer.py m <lba-hex> <sectors-hex> <out-file>   (eMMC sectors)

Protocol: reply = b"OKAY" + 16 lowercase hex digits (byte count), then the
raw payload as 512-byte bulk packets on EP1 IN.

Transport notes learned on-target (2026-10-06):
- The kernel dispatches a command on the FIRST EP1-OUT write; a blind second
  write can hang in the DWC2 (no drainer for it) - so send once, and only
  re-send if no reply arrives within a few seconds.
- A stale reply fragment from a previous session can sit ahead of ours; the
  deep drain at start plus the OKAY-scan handles it.
- FB_XFER_WINDOW overrides the overall read patience (default 240 s).
"""
import os
import sys
import time

import usb.core
import usb.util

if len(sys.argv) != 5:
    print(__doc__)
    sys.exit(1)
kind, arg, cnt, out_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
if kind not in ("r", "m"):
    print("kind must be r or m")
    sys.exit(1)

window = float(os.environ.get("FB_XFER_WINDOW", "240"))

dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
if dev is None:
    print("device not found")
    sys.exit(1)
try:
    dev.set_configuration()
except Exception:
    pass
time.sleep(0.5)
try:
    usb.util.claim_interface(dev, 0)
except Exception as e:
    print("claim:", e)

# Deep drain: eat any stale reply fragments.
quiet = 0
t0 = time.time()
while quiet < 10 and time.time() - t0 < 45:
    try:
        r = bytes(dev.read(0x81, 65536, timeout=1500))
        if r:
            quiet = 0
        else:
            quiet += 1
    except usb.core.USBError as e:
        if e.errno == 110:
            quiet += 1
        else:
            print("drainerr:", e)
            quiet += 1

cmd = f"oem xfer {kind} {arg} {cnt}".encode()


def do_dance():
    """Re-arm EP1 via SET_CONFIGURATION(0)->(1); the kernel re-inits EP1 only
    on the (1) edge, which is the documented recovery from a wedged
    endpoint."""
    try:
        dev.ctrl_transfer(0x00, 9, 0, 0, None, timeout=10000)
    except Exception as e:
        print("cfg0:", e, flush=True)
    time.sleep(0.5)
    try:
        dev.ctrl_transfer(0x00, 9, 1, 0, None, timeout=30000)
    except Exception as e:
        print("cfg1:", e, flush=True)
    time.sleep(5)
    try:
        usb.util.claim_interface(dev, 0)
    except Exception:
        pass


def write_once():
    try:
        dev.write(0x01, cmd, timeout=8000)
        return True
    except usb.core.USBError as e:
        print("write:", e)
        return False


def read_all(recover):
    """Read until the OKAY header + payload are complete. On a stream error
    (EIO = the endpoint wedged after a previous conversation) run the dance
    once and retry the whole transfer."""
    got = bytearray()
    header_len = None
    payload_start = None
    eio_printed = False
    overflows = 0
    last_progress = 0
    t0 = time.time()
    while time.time() - t0 < window:
        try:
            # v222: 4 KiB reads instead of one 64 KiB URB - smaller URBs
            # complete more predictably on this device and the EOVERFLOW
            # bursts become per-read events we can ride through.
            r = bytes(dev.read(0x81, 4096, timeout=3000))
        except usb.core.USBError as e:
            if e.errno == 75:
                # EOVERFLOW: transient; keep draining without sleeping.
                overflows += 1
                if overflows % 64 == 1:
                    print("overflow x", overflows, " got", len(got), flush=True)
                continue
            if e.errno != 110:
                # Print once, then back off: a wedged endpoint raises EIO
                # instantly, and printing each one floods the caller's log
                # (measured: 7.9M lines / 300 MB in one 300 s window).
                if not eio_printed:
                    print("readerr:", e, flush=True)
                    eio_printed = True
                time.sleep(0.05)
            r = b""
        if r:
            got += r
            if len(got) - last_progress >= 65536:
                last_progress = len(got)
                print("progress:", len(got), "bytes", flush=True)
            if payload_start is None:
                # Scan for an OKAY whose 16 hex digits actually parse: the
                # TX FIFO can carry stale reply fragments ahead of ours (a
                # doubled "OKAYOKAY..." was measured), so the first OKAY is
                # not necessarily ours.
                i = 0
                while True:
                    i = got.find(b"OKAY", i)
                    if i < 0 or len(got) < i + 20:
                        break
                    try:
                        header_len = int(bytes(got[i + 4 : i + 20]), 16)
                    except ValueError:
                        i += 1
                        continue
                    payload_start = i + 20
                    print("OKAY len:", header_len, flush=True)
                    break
            if payload_start is not None and len(got) - payload_start >= header_len:
                return bytes(got[payload_start : payload_start + header_len])
        elif eio_printed and recover:
            print("EIO - dancing and retrying once", flush=True)
            do_dance()
            write_once()
            return read_all(False)
    if payload_start is None:
        print("no OKAY header; got bytes:", len(got))
        return None
    return bytes(got[payload_start : payload_start + header_len])


write_once()
print("sent:", cmd.decode(), flush=True)
payload = read_all(True)
if payload is None:
    sys.exit(2)
with open(out_path, "wb") as f:
    f.write(payload)
print(f"wrote {len(payload)} bytes to {out_path}")
