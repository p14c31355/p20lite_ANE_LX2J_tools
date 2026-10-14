#!/usr/bin/env python3
"""Find the PCUI port among the three manufacture-mode vendor interfaces.

The C# tool this mirrors (werasik2aa/Huawei-Unlock-Tool, HuaweiUnlock/DIAGNOS/DIAG.cs) opens a port it
calls PCUI at 115200 and sends plain AT commands on it, then sends `AT$QCDMG=115200` to switch the
device into DIAG mode. Which USB interface that is, the source does not say - its port is picked from
a Windows COM list by name. So: ask each candidate with `AT` and keep the one that answers.

Read-only apart from the AT command itself, which is the documented, intended use of this port.
"""
import sys
import time
import usb.core
import usb.util

VID, PID = 0x12D1, 0x107E
CANDIDATES = [0, 1, 2]          # class 255 / subclass 19 (protocols 33, 34, 35)
TIMEOUT_MS = 700

def find_endpoints(dev, itf_num):
    cfg = dev.get_active_configuration()
    itf = cfg[(itf_num, 0)]
    out_ep = in_ep = None
    for ep in itf:
        if usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_OUT:
            if usb.util.endpoint_type(ep.bmAttributes) == usb.util.ENDPOINT_TYPE_BULK:
                out_ep = ep
        else:
            if usb.util.endpoint_type(ep.bmAttributes) == usb.util.ENDPOINT_TYPE_BULK:
                in_ep = ep
    return itf, out_ep, in_ep

def drain(dev, ep, rounds=4):
    got = b""
    for _ in range(rounds):
        try:
            chunk = dev.read(ep.bEndpointAddress, 4096, timeout=120)
            got += bytes(chunk)
        except usb.core.USBError:
            break
    return got

def main():
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        print("device not found - is it in Manufacture Mode?")
        return 1
    print(f"found {VID:04x}:{PID:04x} bus={dev.bus} addr={dev.address}")

    results = {}
    for itf_num in CANDIDATES:
        try:
            itf, out_ep, in_ep = find_endpoints(dev, itf_num)
        except Exception as exc:                       # noqa: BLE001
            print(f"  itf {itf_num}: descriptor error {exc}")
            continue
        if out_ep is None or in_ep is None:
            print(f"  itf {itf_num}: no bulk pair")
            continue
        detached = False
        try:
            if dev.is_kernel_driver_active(itf_num):
                dev.detach_kernel_driver(itf_num)
                detached = True
        except Exception:                              # noqa: BLE001
            pass
        try:
            usb.util.claim_interface(dev, itf_num)
        except Exception as exc:                       # noqa: BLE001
            print(f"  itf {itf_num}: claim failed {exc} (permissions?)")
            continue
        try:
            drain(dev, in_ep)
            out_ep.write(b"AT\r")
            time.sleep(0.2)
            data = drain(dev, in_ep)
            printable = "".join(chr(c) if 32 <= c < 127 else "." for c in data)[:60]
            print(f"  itf {itf_num} (proto {itf.bInterfaceProtocol}): "
                  f"ep_out=0x{out_ep.bEndpointAddress:02x} ep_in=0x{in_ep.bEndpointAddress:02x} "
                  f"reply={len(data)}B {printable!r}")
            results[itf_num] = (len(data), printable)
        except Exception as exc:                       # noqa: BLE001
            print(f"  itf {itf_num}: io error {exc}")
        finally:
            try:
                usb.util.release_interface(dev, itf_num)
            except Exception:                          # noqa: BLE001
                pass
            if detached:
                try:
                    dev.attach_kernel_driver(itf_num)
                except Exception:                      # noqa: BLE001
                    pass

    answered = [n for n, (ln, txt) in results.items() if ln > 0]
    print("answered:", answered)
    if answered:
        print("PCUI candidate:", answered[0])
    return 0

if __name__ == "__main__":
    sys.exit(main())
