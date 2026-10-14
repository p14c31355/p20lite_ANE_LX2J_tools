#!/bin/bash
cd ~/dev/hi6250-src/drivers/usb/dwc2 || exit 1
echo "=== gadget.c around 470-560 (ep0 xfer length setup) ==="
sed -n '470,560p' gadget.c
echo
echo "=== any dieptsiz writes ==="
grep -n "dieptsiz\b\|DIEPTSIZ0\|dieptsiz0" gadget.c | head -15
