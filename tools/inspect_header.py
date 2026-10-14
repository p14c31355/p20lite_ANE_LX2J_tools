#!/usr/bin/env python3
"""
UPDATE.APP begins with an RSA signature block and a CRC block, then the
partition images. The header region carries the table of contents - partition
names and their versions - which is what tells us whether the write at 5% was
refused because the incoming image is a LOWER version than what is on the device
(anti-rollback), as opposed to some signature or packaging problem.
"""
import re
import zipfile

Z = "/tmp/fw3/Software/dload/update_sd.zip"
z = zipfile.ZipFile(Z)

N = 2 * 1024 * 1024   # first 2 MB of the image is plenty for the TOC
with z.open("UPDATE.APP") as f:
    head = f.read(N)
print(f"read {len(head):,} bytes\n")

print("########## human strings in the header region")
strs = re.findall(rb"[ -~]{4,64}", head)
seen = set()
order = []
for s in strs:
    t = s.decode("ascii", "replace")
    if t not in seen:
        seen.add(t)
        order.append(t)
for t in order[:120]:
    print("   ", t)

print()
print("########## partition-ish names present anywhere in the header")
names = ["xloader", "fastboot", "boot", "recovery", "system", "vendor", "product",
         "cust", "userdata", "cache", "modem", "modemnvm", "nvme", "teeos", "trustfirmware",
         "erecovery", "vbmeta", "dtbo", "splash", "version", "ptable", "curver", "verlist"]
low = head.lower()
for n in names:
    hits = [m.start() for m in re.finditer(n.encode(), low)]
    if hits:
        ctx = head[max(0, hits[0] - 40):hits[0] + 60]
        ctxs = re.sub(rb"[^ -~]", ".", ctx).decode("ascii", "replace")
        print(f"  {n:16} x{len(hits):<3} first@{hits[0]:#08x}  ...{ctxs}...")
