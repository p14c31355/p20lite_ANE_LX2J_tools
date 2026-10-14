#!/usr/bin/env python3
"""Decode the UD: Q= trace words across the collected rings."""
import re
from collections import Counter

for tag in ["v306_zero3_b1", "v306_zero3_b2", "v306_zero3_b3", "v306_zero3_b4", "v306_zero5"]:
    data = open(f"/home/placeless/dev/p20-root/rings_night/{tag}.bin", "rb").read()
    txt = data[24:].decode("ascii", "replace")
    qs = re.findall(r"Q=([0-9A-F]{8}) ([0-9A-F]{8})", txt)
    c = Counter(qs)
    print("==", tag, len(qs), "requests")
    for (w0, w1), n in c.most_common(14):
        bmr = int(w0[0:2], 16)
        breq = int(w0[2:4], 16)
        # setup: w0 = bmRequestType(1) bRequest(1) wValue LE(2); w1 = wIndex(2) wLength(2)
        wvalue = int(w0[4:6] + w0[6:8], 16)
        wlen = int(w1[4:6] + w1[6:8], 16)
        print(f"  {w0} {w1} x{n}   bm=0x{bmr:02x} req=0x{breq:02x} wVal=0x{wvalue:04x} wLen={wlen}")
