#!/usr/bin/env python3
"""Raw USB probe of the in-kernel fastboot responder (18d1:d00d).

Sends a getvar command straight to EP1-OUT and tries to read the EP1-IN
response, reporting exactly where (write vs read) the exchange breaks.
Usage: python3 probe_fb.py [--nul] [--cmd getvar:version]
"""
import sys
import time

import usb.core

dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
if dev is None:
    print("NO DEVICE 18d1:d00d")
    sys.exit(1)
print(f"device found: bus={dev.bus} addr={dev.address}")

try:
    cfg = dev.get_active_configuration()
    print(f"active config: {cfg.bConfigurationValue}")
except Exception as e:  # noqa: BLE001
    print(f"config read: {type(e).__name__}: {e}")

cmd = sys.argv[-1] if len(sys.argv) > 1 and not sys.argv[-1].startswith("--") else "getvar:version"
wire = cmd.encode() + (b"\x00" if "--nul" in sys.argv else b"")
print(f"sending {len(wire)} bytes: {wire!r}")

t0 = time.time()
try:
    n = dev.write(0x01, wire, timeout=3000)
    print(f"OUT write: OK ({n} bytes) after {time.time()-t0:.2f}s")
except Exception as e:  # noqa: BLE001
    print(f"OUT write: FAIL after {time.time()-t0:.2f}s: {type(e).__name__}: {e}")
    sys.exit(2)

t0 = time.time()
try:
    r = dev.read(0x81, 64, timeout=5000)
    print(f"IN read: OK after {time.time()-t0:.2f}s: {bytes(r)!r}")
except Exception as e:  # noqa: BLE001
    print(f"IN read: FAIL after {time.time()-t0:.2f}s: {type(e).__name__}: {e}")
    sys.exit(3)
