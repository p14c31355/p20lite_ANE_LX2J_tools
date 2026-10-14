#!/usr/bin/env python3
"""
Inspect how the ORIGINAL encodes entries larger than 4 GB, and what extra fields
it uses, so a hand-written zip can mirror it exactly.

UPDATE.APP is 4,340,264,812 bytes uncompressed, which does not fit in the 32-bit
uncompressed-size field, so ZIP64 must be in play. The central directory record is
46 bytes plus name/extra/comment; the ZIP64 values live in an extra field with
header ID 0x0001.
"""
import struct

P = "/tmp/fw3/Software/dload/update_sd.zip"
data = open(P, "rb").read()
EOCD_SIG = b"PK\x05\x06"
CEN_SIG = b"PK\x01\x02"

# locate EOCD the strict way
pos = None
i = data.find(EOCD_SIG)
while i != -1:
    if i + 22 <= len(data):
        clen = struct.unpack("<H", data[i + 20:i + 22])[0]
        if i + 22 + clen == len(data):
            pos = i
    i = data.find(EOCD_SIG, i + 1)
print(f"EOCD @{pos:#x}")
disk, cd_disk, n_disk, n_total, cd_size, cd_off, clen = struct.unpack("<HHHHIIH", data[pos + 4:pos + 22])
print(f"entries={n_total} cd_off={cd_off:#x} cd_size={cd_size}")

cd = data[cd_off:cd_off + cd_size]
p = 0
while p < len(cd):
    f = struct.unpack("<IHHHHHHIIIHHHHHII", cd[p:p + 46])
    nlen, elen, clen2 = f[10], f[11], f[12]
    name = cd[p + 46:p + 46 + nlen]
    extra = cd[p + 46 + nlen:p + 46 + nlen + elen]
    print(f"\n{name.decode()}")
    print(f"   version_made={f[1]:#06x} needed={f[2]:#06x} flags={f[3]:#06x} method={f[4]}")
    print(f"   crc={f[7]:#010x} csize={f[8]} usize={f[9]} disk={f[13]} iattr={f[14]:#06x} eattr={f[15]:#010x} doff={f[16]:#x}")
    print(f"   name_len={nlen} extra_len={elen} comment_len={clen2}")
    if extra:
        print(f"   EXTRA ({elen} bytes): {extra.hex()}")
        q = 0
        while q + 4 <= len(extra):
            hid, hsz = struct.unpack("<HH", extra[q:q + 4])
            body = extra[q + 4:q + 4 + hsz]
            print(f"     field id={hid:#06x} size={hsz} data={body.hex()}")
            if hid == 0x0001:
                vals, r = [], 0
                for label, need in (("usize", f[9] == 0xFFFFFFFF), ("csize", f[8] == 0xFFFFFFFF),
                                    ("doff", f[16] == 0xFFFFFFFF), ("disk", f[13] == 0xFFFF)):
                    if need and r + 8 <= len(body):
                        vals.append((label, struct.unpack("<Q", body[r:r + 8])[0]))
                        r += 8
                print(f"     -> ZIP64 values: {vals}")
            q += 4 + hsz
    p += 46 + nlen + elen + clen2
