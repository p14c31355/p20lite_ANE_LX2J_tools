#!/usr/bin/env python3
"""Try the mode-switch command variants on every manufacture-mode vendor interface.

The C# tool sends `AT$QCDMG=115200\\r` on a port it calls PCUI. On this unit interface 1 (protocol 34)
answers plain AT with OK but rejects that command with "no permission". Two things can differ: which
interface is really PCUI, and which spelling the firmware accepts. Both are settled by trying them.

Only AT-style text commands are sent - the documented use of these ports - and every reply is logged.
"""
import sys
import time
import usb.core
import usb.util

VID, PID = 0x12D1, 0x107E
VARIANTS = [
    b"AT\r",
    b"AT$QCDMG=115200\r",
    b"AT^QCDMG=115200\r",
    b"AT$QCDMG\r",
    b"AT^QCDMG\r",
    b"AT+QCDMG=115200\r",
]

def bulk_pair(cfg, itf_num):
    itf = cfg[(itf_num, 0)]
    out_ep = in_ep = None
    for ep in itf:
        if usb.util.endpoint_type(ep.bmAttributes) != usb.util.ENDPOINT_TYPE_BULK:
            continue
        if usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_OUT:
            out_ep = ep
        else:
            in_ep = ep
    return itf, out_ep, in_ep

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
    print(f"device {VID:04x}:{PID:04x} addr={dev.address}")
    for itf_num in (0, 1, 2):
        itf, out_ep, in_ep = bulk_pair(cfg, itf_num)
        if out_ep is None or in_ep is None:
            print(f"itf {itf_num}: no bulk pair")
            continue
        print(f"--- interface {itf_num} (protocol {itf.bInterfaceProtocol}) "
              f"out=0x{out_ep.bEndpointAddress:02x} in=0x{in_ep.bEndpointAddress:02x}")
        detached = False
        try:
            if dev.is_kernel_driver_active(itf_num):
                dev.detach_kernel_driver(itf_num)
                detached = True
        except Exception:                                  # noqa: BLE001
            pass
        try:
            usb.util.claim_interface(dev, itf_num)
        except Exception as exc:                           # noqa: BLE001
            print(f"    claim failed: {exc}")
            continue
        try:
            for cmd in VARIANTS:
                try:
                    dev.write(out_ep.bEndpointAddress, cmd, timeout=1000)
                except usb.core.USBError as exc:
                    print(f"    {cmd!r}: write failed {exc}")
                    continue
                data = read_all(dev, in_ep, 700)
                text = "".join(chr(c) if 32 <= c < 127 else "." for c in data)[:70]
                print(f"    {cmd!r}: {len(data)}B {text!r}")
                time.sleep(0.3)
        finally:
            try:
                usb.util.release_interface(dev, itf_num)
            except Exception:                              # noqa: BLE001
                pass
            if detached:
                try:
                    dev.attach_kernel_driver(itf_num)
                except Exception:                          # noqa: BLE001
                    pass
    return 0

if __name__ == "__main__":
    sys.exit(main())
