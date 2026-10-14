#!/usr/bin/env python3
"""Ask the PCUI port (interface 1, protocol 34) what it knows.

Read-only AT queries. `AT^GETPORTMODE` is the ModemManager-documented way to have a Huawei device
name its own USB port layout (PCUI / MDM / DIAG / NDIS), which tells us which interface the vendor
tools mean by PCUI and whether a DBAdapter port exists. The rest are ordinary identity queries.
"""
import sys
import time
import usb.core
import usb.util

VID, PID = 0x12D1, 0x107E
ITF = 1
QUERIES = [
    b"AT\r",
    b"ATI\r",
    b"AT^VERSION\r",
    b"AT+CGSN\r",
    b"AT^GETPORTMODE\r",
    b"AT+CIMI\r",
]

def read_all(dev, ep, ms):
    out = b""
    deadline = time.time() + ms / 1000.0
    while time.time() < deadline:
        try:
            out += bytes(dev.read(ep.bEndpointAddress, 4096, timeout=250))
        except usb.core.USBError:
            pass
    return out

def main():
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        print("device not found")
        return 1
    cfg = dev.get_active_configuration()
    itf = cfg[(ITF, 0)]
    out_ep = in_ep = None
    for ep in itf:
        if usb.util.endpoint_type(ep.bmAttributes) != usb.util.ENDPOINT_TYPE_BULK:
            continue
        if usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_OUT:
            out_ep = ep
        else:
            in_ep = ep
    detached = False
    try:
        if dev.is_kernel_driver_active(ITF):
            dev.detach_kernel_driver(ITF)
            detached = True
    except Exception:                                      # noqa: BLE001
        pass
    usb.util.claim_interface(dev, ITF)
    try:
        for cmd in QUERIES:
            try:
                dev.write(out_ep.bEndpointAddress, cmd, timeout=1000)
            except usb.core.USBError as exc:
                print(f"{cmd!r}: write failed {exc}")
                continue
            data = read_all(dev, in_ep, 900)
            text = "".join(chr(c) if 32 <= c < 127 else "." for c in data)[:120]
            print(f"{cmd!r}: {len(data)}B {text!r}")
            time.sleep(0.3)
    finally:
        try:
            usb.util.release_interface(dev, ITF)
        except Exception:                                  # noqa: BLE001
            pass
        if detached:
            try:
                dev.attach_kernel_driver(ITF)
            except Exception:                              # noqa: BLE001
                pass
    return 0

if __name__ == "__main__":
    sys.exit(main())
