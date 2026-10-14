#!/usr/bin/env python3
"""
Inspect the ZIP comment area of update_sd.zip.

CVE-2021-40045 (taszk.io): Huawei stores the update package signature inside the
ZIP end-of-central-directory (EOCD) comment field. The verifier parses the FIRST
EOCD and checks the signature over everything before the comment; minzip, the
extractor, walks backwards from the end of the file and therefore finds the LAST
EOCD. Smuggling a second, complete ZIP inside the comment makes the verifier see
the pristine package while the extractor reads our modified one.

Before building that, look at what is actually there.
"""
import struct
import zipfile

P = "/tmp/fw3/Software/dload/update_sd.zip"
data = open(P, "rb").read()
size = len(data)
print(f"file size: {size:,}")

# Locate EOCD by scanning backwards for its signature.
EOCD_SIG = b"PK\x05\x06"

# 1. does the plain zip parser see the real entries?
with zipfile.ZipFile(P) as z:
    print("\nzipfile sees these entries:")
    for i in z.infolist():
        print(f"   {i.file_size:>12} {i.filename}")

# 2. find every EOCD signature in the tail
print("\nall EOCD signatures in the last 64 KB:")
start = max(0, size - 65536)
pos = data.find(EOCD_SIG, start)
found = []
while pos != -1:
    if pos + 22 <= size:
        (disk, cd_disk, n_disk, n_total, cd_size, cd_off, clen) = struct.unpack(
            "<HHHHIIH", data[pos + 4:pos + 22])
        found.append((pos, clen))
        print(f"   @{pos:#x}  comment_len={clen}  cd_off={cd_off:#x} cd_size={cd_size} "
              f"entries={n_total}  (pos+22+clen = {pos+22+clen}, file end = {size})")
    pos = data.find(EOCD_SIG, pos + 1)

if found:
    pos, clen = found[0]
    comment = data[pos + 22:pos + 22 + clen]
    print(f"\nfirst EOCD comment: {clen} bytes")
    print("  first 64 bytes:", comment[:64])
    print("  last 32 bytes:", comment[-32:])
    print("  trailing bytes after comment:", size - (pos + 22 + clen))
