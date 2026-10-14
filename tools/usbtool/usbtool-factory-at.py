#!/usr/bin/env python3
"""Probe the manufacture-mode PCUI port with Huawei's *factory* AT command set.

Everything except a bare "AT" previously answered "no permission", but those
were all consumer/modem commands. Manufacture mode exists for factory
operations, so the factory-only commands may sit inside the allow-list:
  AT^SFM     - switch to factory mode (this is the one that matters)
  AT^NVRDEX  - read an NV item (read-only, safe)
  AT^U2DIAG  - mode switch (query form only)
  AT^CARDLOCK- query form only
Note: AT^NVWREX WRITES NV (it is Huawei's universal unlock) - deliberately NOT
sent here, a wrong index/value could damage the NV store.
"""
import sys
import time
import usb.core
import usb.util

VID, PID = 0x12D1, 0x107E

QUERIES = [
    "AT^SFM?",          # current factory-mode state
    "AT^SFM=0",         # idempotent-ish: ensure *not* left in factory mode
    "AT^NVRDEX?",
    "AT^U2DIAG?",
    "AT^CARDLOCK?",
    "AT^HWVER",
    "AT^VERSION?",
    "AT^GETPORTMODE",
    "AT+CGSN",
]
ACTIONS = [
    "AT^SFM=1",         # switch to factory mode - the candidate mechanism
]


def find_pcui():
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        return None, None, None
    try:
        dev.set_configuration()
    except Exception:
        pass
    for cfg in dev:
        for intf in cfg:
            if intf.bInterfaceNumber == 1:   # protocol 34 = PCUI
                ep_in = ep_out = None
                for ep in intf:
                    d = usb.util.endpoint_direction(ep.bEndpointAddress)
                    if d == usb.util.ENDPOINT_OUT:
                        ep_out = ep
                    elif d == usb.util.ENDPOINT_IN:
                        ep_in = ep
                if ep_in and ep_out:
                    return dev, ep_in, ep_out
    return dev, None, None


def send(dev, ep_in, ep_out, cmd, wait=0.6):
    # The AT parser needs a CR terminator; without it the port answers "no
    # permission" even for a bare AT (measured 2026-10-01).
    payload = (cmd + "\r").encode("ascii")
    try:
        dev.write(ep_out.bEndpointAddress, payload, timeout=3000)
    except usb.core.USBError as e:
        return f"write error: {e}"
    time.sleep(wait)
    try:
        data = dev.read(ep_in.bEndpointAddress, 256, timeout=3000)
        return data.tobytes().decode("ascii", "replace").strip().replace("\r", "")
    except usb.core.USBTimeoutError:
        return "(timeout / no reply)"


def main():
    dev, ep_in, ep_out = find_pcui()
    if dev is None:
        print("device 12d1:107e not found - is it connected?")
        return 1
    if ep_out is None:
        print("PCUI interface 1 not present - set Manufacture Mode in ProjectMenu")
        return 1
    print(f"PCUI: out=0x{ep_out.bEndpointAddress:02x} in=0x{ep_in.bEndpointAddress:02x}")

    print(f"\n=== sanity: bare AT ===\n{send(dev, ep_in, ep_out, 'AT')}")
    print("\n=== factory queries ===")
    for c in QUERIES:
        print(f"{c:24s} -> {send(dev, ep_in, ep_out, c)}")
    print("\n=== actions ===")
    for c in ACTIONS:
        print(f"{c:24s} -> {send(dev, ep_in, ep_out, c, wait=1.5)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
