#!/usr/bin/env python3
"""
Walk the newc cpio properly and pull out the recovery binary.

Bug in the first attempt: in newc format every header field is EIGHT ASCII HEX
characters, not a binary integer. The header is 6 + 13*8 = 110 bytes.

Then dump sbin/recovery's strings to learn exactly which files and formats the
pre-checks demand - these are the checks that abort our update at ~5%.
"""
import os
import re
import struct

CPIO = "/tmp/recov/recovery_ramdisk.cpio"
OUT = "/tmp/recov"
raw = open(CPIO, "rb").read()
print(f"cpio: {len(raw):,} bytes")

files = []
p = 0
while p + 110 <= len(raw):
    hdr = raw[p:p + 110]
    if hdr[:6] not in (b"070701", b"070702"):
        nxt = raw.find(b"070701", p)
        if nxt == -1:
            break
        p = nxt
        continue
    f = lambda i: int(hdr[6 + 8 * i: 6 + 8 * (i + 1)], 16)
    mode, filesize, namesize = f(1), f(6), f(11)
    name = raw[p + 110:p + 110 + namesize - 1].decode("utf-8", "replace")
    body = p + 110 + namesize
    body += (-body) % 4
    data = raw[body:body + filesize]
    files.append((name, mode, filesize, data))
    body += filesize
    body += (-body) % 4
    p = body
    if name == "TRAILER!!!":
        break

print(f"entries: {len(files)}")
for n, m, s, _ in files:
    if re.search(r"sbin/|recovery|\.zip$|\.tag$|\.mbn$|init\.rc|prop", n):
        print(f"   {m:07o} {s:>10,} {n}")

# dump the recovery binary
cand = [x for x in files if x[0].endswith("sbin/recovery")]
if not cand:
    cand = [x for x in files if x[0].endswith("/recovery") and x[2] > 1_000_000]
print("\nbinary candidates:", [(c[0], c[2]) for c in cand])
for name, mode, size, data in cand:
    path = os.path.join(OUT, "recovery.bin")
    open(path, "wb").write(data)
    print(f"wrote {path} from {name} ({size:,} bytes)")
