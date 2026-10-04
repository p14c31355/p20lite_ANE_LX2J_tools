#!/usr/bin/env python3
"""
Two questions:
 1. Is SOFTWARE_VER_LIST.mbn covered by the JAR signature? If it is, editing it
    should have failed *before* the progress bar moved - and the bar DID move to
    5%, so the write phase had already started.
 2. What is the FIRST thing UPDATE.APP writes? Huawei's UPDATE.APP is a sequence
    of 256-byte-header entries; the first entry name is the first partition
    written, i.e. whatever was refused at 5%.
"""
import zipfile

Z = "/tmp/fw3/Software/dload/update_sd.zip"
z = zipfile.ZipFile(Z)

print("########## what the signature actually covers")
man = z.read("META-INF/MANIFEST.MF").decode("utf-8", "replace")
print("--- META-INF/MANIFEST.MF")
print(man)
print("--- META-INF/CERT.SF")
sf = z.read("META-INF/CERT.SF").decode("utf-8", "replace")
print(sf)

print()
print("########## does the manifest mention our edited file?")
for name in ("SOFTWARE_VER_LIST.mbn", "UPDATE.APP", "update-binary", "SD_update.tag"):
    print(f"  {name:24} in MANIFEST: {name in man}   in CERT.SF: {name in sf}")

print()
print("########## first entries of UPDATE.APP (write order)")
with z.open("UPDATE.APP") as f:
    head = f.read(64 * 1024)
print(f"read {len(head)} bytes of the header area")

# Entry headers are 256-byte aligned; filenames are NUL-terminated ASCII.
i = 0
seen = 0
while i < len(head) - 256 and seen < 14:
    block = head[i:i + 256]
    # find a plausible NUL-terminated name near the start of the block
    txt = block.split(b"\x00")
    cands = [t for t in txt if 3 <= len(t) <= 40 and all(32 <= c < 127 for c in t)]
    if cands:
        name = cands[0].decode("ascii", "replace")
        ver = " | ".join(c.decode("ascii", "replace") for c in cands[1:4])
        print(f"  block {i//256:>3} @0x{i:06x}: name={name!r}  extra={ver!r}")
        seen += 1
        i += 256
    else:
        i += 256
