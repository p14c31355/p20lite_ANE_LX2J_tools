#!/usr/bin/env python3
"""Logically replug the ANE-LX2J's USB port, as the user (no root needed).

The phone's usbfs node is root:plugdev with an ACL for this account (that is
why adb works), so a USBDEVFS_RESET ioctl - a port reset, the software
equivalent of pulling and re-inserting the cable - is available without sudo.
That is the same stimulus the root helper (`ane_usb_revive_root.sh`) applies
through the authorized toggle, just from the device side instead of sysfs.

Usage: ane_usb_reset_user.py [--settle 2] [--repeat 1]
"""
import fcntl
import os
import pathlib
import sys
import time

USBDEVFS_RESET = 0x5514  # _IO('U', 20)


def find_phone_node(vendor="12d1"):
    for entry in pathlib.Path("/sys/bus/usb/devices").iterdir():
        vendor_file = entry / "idVendor"
        if not vendor_file.exists():
            continue
        if vendor_file.read_text().strip() != vendor:
            continue
        busnum = int((entry / "busnum").read_text())
        devnum = int((entry / "devnum").read_text())
        node = pathlib.Path(f"/dev/bus/usb/{busnum:03d}/{devnum:03d}")
        product = (entry / "product")
        return node, (product.read_text().strip() if product.exists() else "?")
    return None, None


def main():
    settle = 2.0
    repeat = 1
    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a == "--settle" and i + 1 < len(args):
            settle = float(args[i + 1])
        if a == "--repeat" and i + 1 < len(args):
            repeat = int(args[i + 1])

    for round_no in range(1, repeat + 1):
        node, product = find_phone_node()
        if node is None:
            print("no 12d1 device on the bus")
            return 2
        print(f"[{time.strftime('%H:%M:%S')}] round {round_no}: resetting {node} ({product})")
        try:
            fd = os.open(node, os.O_RDWR)
        except PermissionError as exc:
            print(f"  cannot open node: {exc}")
            return 3
        try:
            fcntl.ioctl(fd, USBDEVFS_RESET)
        except OSError as exc:
            print(f"  ioctl failed: {exc}")
            return 4
        finally:
            os.close(fd)
        print(f"  reset issued; settling {settle:.0f}s")
        time.sleep(settle)
    return 0


if __name__ == "__main__":
    sys.exit(main())
