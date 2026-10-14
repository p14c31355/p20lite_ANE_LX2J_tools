#!/usr/bin/env python3
"""Send the mode-switch AT command that puts the phone into DIAG / download mode.

Source of the command: werasik2aa/Huawei-Unlock-Tool, HuaweiUnlock/DIAGNOS/DIAG.cs:
    SW_PCUI_TODIAG():  AT_SEND("AT$QCDMG=115200\r")     // PCUI port, 115200
i.e. the documented "software testpoint": the PCUI port is switched to DIAG, which is what the
vendor tools do without opening the phone. Port identified by probing: interface 1 (protocol 34),
endpoints 0x02/0x82 - it is the only one of the three that answers plain AT.

After this, the device is expected to re-enumerate - ideally as 12d1:3609 (HUAWEI USB COM 1.0),
which is the interface PotatoNV/usrlock speaks.
"""
import sys
import time
import usb.core
import usb.util

VID, PID = 0x12D1, 0x107E
PCUI_ITF = 1
CMD = b"AT$QCDMG=115200\r"

def main():
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        print("device not found - is it still in Manufacture Mode?")
        return 1
    print(f"device {VID:04x}:{PID:04x} bus={dev.bus} addr={dev.address}")

    cfg = dev.get_active_configuration()
    itf = cfg[(PCUI_ITF, 0)]
    out_ep = in_ep = None
    for ep in itf:
        if usb.util.endpoint_type(ep.bmAttributes) != usb.util.ENDPOINT_TYPE_BULK:
            continue
        if usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_OUT:
            out_ep = ep
        else:
            in_ep = ep
    print(f"PCUI interface {PCUI_ITF}: out=0x{out_ep.bEndpointAddress:02x} in=0x{in_ep.bEndpointAddress:02x}")

    detached = False
    try:
        if dev.is_kernel_driver_active(PCUI_ITF):
            dev.detach_kernel_driver(PCUI_ITF)
            detached = True
    except Exception:                                     # noqa: BLE001
        pass
    usb.util.claim_interface(dev, PCUI_ITF)
    try:
        # sanity first: is this still the AT port?
        out_ep.write(b"AT\r")
        time.sleep(0.2)
        try:
            echo = bytes(dev.read(in_ep.bEndpointAddress, 4096, timeout=700))
        except usb.core.USBError:
            echo = b""
        print(f"sanity AT reply: {echo!r}")

        print(f"sending {CMD!r} ...")
        out_ep.write(CMD)
        time.sleep(0.5)
        try:
            reply = bytes(dev.read(in_ep.bEndpointAddress, 4096, timeout=1500))
        except usb.core.USBError as exc:
            reply = b""
            print(f"(no reply read: {exc})")
        text = "".join(chr(c) if 32 <= c < 127 else "." for c in reply)
        print(f"reply {len(reply)}B {text!r}")
    finally:
        try:
            usb.util.release_interface(dev, PCUI_ITF)
        except Exception:                                 # noqa: BLE001
            pass
        if detached:
            try:
                dev.attach_kernel_driver(PCUI_ITF)
            except Exception:                             # noqa: BLE001
                pass
    print("command sent - the device should now re-enumerate")
    return 0

if __name__ == "__main__":
    sys.exit(main())
