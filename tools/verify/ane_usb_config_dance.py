#!/usr/bin/env python3
"""Re-configure the ANE-LX2J's USB device from the host, as the user.

SET_CONFIGURATION(0) then SET_CONFIGURATION(<original>): the device sees its
configuration torn down and re-set, which makes the composite gadget re-bind
its functions - a stronger reconnect-like stimulus than a port reset. Both
requests are plain usbfs control transfers, available without root for the
same reason adb works (the node is root:plugdev with an ACL).

Usage: ane_usb_config_dance.py [--settle 3]
"""
import ctypes
import fcntl
import os
import pathlib
import sys
import time

USBDEVFS_CONTROL = 0xC0185500


class CtrlTransfer(ctypes.Structure):
    _fields_ = [
        ("bRequestType", ctypes.c_uint8),
        ("bRequest", ctypes.c_uint8),
        ("wValue", ctypes.c_uint16),
        ("wIndex", ctypes.c_uint16),
        ("wLength", ctypes.c_uint16),
        ("timeout", ctypes.c_uint32),
        ("data", ctypes.c_void_p),
    ]


def find_phone_node(vendor="12d1"):
    for entry in pathlib.Path("/sys/bus/usb/devices").iterdir():
        vendor_file = entry / "idVendor"
        if not vendor_file.exists():
            continue
        if vendor_file.read_text().strip() != vendor:
            continue
        busnum = int((entry / "busnum").read_text())
        devnum = int((entry / "devnum").read_text())
        return pathlib.Path(f"/dev/bus/usb/{busnum:03d}/{devnum:03d}"), entry
    return None, None


def read_active_config(entry):
    value = entry / "bConfigurationValue"
    if value.exists():
        try:
            return int(value.read_text().strip())
        except ValueError:
            pass
    return 1


def set_configuration(fd, value):
    transfer = CtrlTransfer()
    transfer.bRequestType = 0x00          # host-to-device, standard, device
    transfer.bRequest = 9                 # SET_CONFIGURATION
    transfer.wValue = value
    transfer.wIndex = 0
    transfer.wLength = 0
    transfer.timeout = 2000
    transfer.data = None
    fcntl.ioctl(fd, USBDEVFS_CONTROL, transfer)


def main():
    settle = 3.0
    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a == "--settle" and i + 1 < len(args):
            settle = float(args[i + 1])

    node, entry = find_phone_node()
    if node is None:
        print("no 12d1 device on the bus")
        return 2
    original = read_active_config(entry)
    print(f"[{time.strftime('%H:%M:%S')}] {node}: active configuration {original}")

    try:
        fd = os.open(node, os.O_RDWR)
    except PermissionError as exc:
        print(f"cannot open node: {exc}")
        return 3
    try:
        set_configuration(fd, 0)
        print("  SET_CONFIGURATION(0) ok; settling")
        time.sleep(settle)
        set_configuration(fd, original)
        print(f"  SET_CONFIGURATION({original}) ok")
    except OSError as exc:
        print(f"  control transfer failed: {exc}")
        return 4
    finally:
        os.close(fd)
    time.sleep(settle)
    return 0


if __name__ == "__main__":
    sys.exit(main())
