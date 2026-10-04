#!/usr/bin/env python3
"""
Read the metadata blocks inside UPDATE.APP: CURVER, VERLIST, PACKAGE_TYPE.

These are the package's own statement of what it is and what it requires. The
ZIP-level SOFTWARE_VER_LIST.mbn we patched is only the outer gate; these blocks sit
inside the signed image, right before the first real partition (XLOADER) - i.e.
exactly where a stop at ~5% would occur.
"""
import struct
import zipfile

Z = "/tmp/fw3/Software/dload/update_sd.zip"
MAGIC = b"\x55\xaa\x5a\xa5"

with zipfile.ZipFile(Z) as z, z.open("UPDATE.APP") as f:
    data = f.read(8 * 1024 * 1024)

pos = data.find(MAGIC)
while pos != -1 and pos + 100 <= len(data):
    hdr_sz, unk1, hw_id, seq, size = struct.unpack("<IIQII", data[pos + 4:pos + 28])
    ptype = data[pos + 60:pos + 76].decode("ascii", "replace").strip("\x00")
    if ptype in ("CURVER", "VERLIST", "PACKAGE_TYPE", "SHA256RSA"):
        payload = data[pos + hdr_sz: pos + hdr_sz + size]
        print(f"########## {ptype}  (@{pos:#x}, {size} bytes)")
        print(f"   hex : {payload.hex()}")
        print(f"   text: {payload!r}")
        try:
            print(f"   text/ascii: {payload.decode('ascii')!r}")
        except UnicodeDecodeError:
            pass
        print()
    nxt = pos + hdr_sz + size
    pos = data.find(MAGIC, nxt)

# also show the CRC block's first bytes for context
pos = data.find(MAGIC)
pos = data.find(MAGIC, pos + 1)
hdr_sz, unk1, hw_id, seq, size = struct.unpack("<IIQII", data[pos + 4:pos + 28])
print(f"########## CRC block header fields")
print(f"   hdr_sz={hdr_sz} seq={seq:#x} size={size:,}")
print(f"   payload head: {data[pos+hdr_sz:pos+hdr_sz+64].hex()}")
