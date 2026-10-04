#!/usr/bin/env python3
"""
Attempt 4: patched content, original signature comment, and the EXACT original
byte count.

The zip is written by hand so that zopfli (a stronger deflate implementation than
zlib's) can compress the small entries. That is what buys the 43 bytes still
missing: the pre-comment part must fit in

    original_size - 22 (EOCD) - 1579 (signature comment) = 2,064,929,691

and a plain level-9 rebuild lands at 2,064,929,756, i.e. 65 bytes over. Shrinking
those 65 bytes from the entries is the whole point.

Structure mirrored exactly from the original (see inspect_zip64.py):
  * the three tiny files are STORED (method 0), and updater-script carries a
    4-byte 0xcafe extra field
  * UPDATE.APP needs a ZIP64 extra field because its uncompressed size exceeds
    32 bits; its 32-bit usize field stays 0xFFFFFFFF
  * version_made / version_needed / flags are copied per entry
  * UPDATE.APP uses plain zlib (4.3 GB is far too slow for zopfli)
"""
import base64
import hashlib
import os
import struct
import zlib

import zopfli.zlib

CRLF = b"\r\n"
TARGET = b"SOFTWARE_VER_LIST.mbn"
EOCD_SIG = b"PK\x05\x06"
ADDITION = None  # replace the cust field in-place instead

JOBS = [
    ("/tmp/fw3/Software/dload/update_sd.zip",
     "/home/placeless/dev/p20-root/firmware/custfix/update_sd.zip"),
    ("/tmp/fw3/Software/dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip",
     "/home/placeless/dev/p20-root/firmware/custfix/update_sd_ANE-L22J_hw_jp.zip"),
]


def raw_deflate_zopfli(data: bytes) -> bytes:
    """zopfli emits a zlib stream; strip the 2-byte header and 4-byte adler."""
    return zopfli.zlib.compress(data)[2:-4]


def raw_deflate_zlib(data: bytes, level=9) -> bytes:
    co = zlib.compressobj(level, zlib.DEFLATED, -15)
    return co.compress(data) + co.flush()


def b64sha1(b: bytes) -> bytes:
    return base64.b64encode(hashlib.sha1(b).digest())


def replace_one(data: bytes, old: bytes, new: bytes) -> bytes:
    assert data.count(old) == 1, f"expected 1 occurrence of {old!r}, got {data.count(old)}"
    return data.replace(old, new)


def read_entries(buf):
    """Full central directory parse, including extras and ZIP64."""
    pos = None
    i = buf.find(EOCD_SIG)
    while i != -1:
        if i + 22 <= len(buf):
            clen = struct.unpack("<H", buf[i + 20:i + 22])[0]
            if i + 22 + clen == len(buf):
                pos = i
        i = buf.find(EOCD_SIG, i + 1)
    assert pos is not None
    disk, cd_disk, n_disk, n_total, cd_size, cd_off, clen = struct.unpack(
        "<HHHHIIH", buf[pos + 4:pos + 22])
    comment = buf[pos + 22:pos + 22 + clen]
    cd = buf[cd_off:cd_off + cd_size]
    out, p = [], 0
    while p < len(cd):
        f = struct.unpack("<IHHHHHHIIIHHHHHII", cd[p:p + 46])
        nlen, elen, clen2 = f[10], f[11], f[12]
        e = dict(ver_made=f[1], ver_need=f[2], flags=f[3], method=f[4], mtime=f[5],
                 mdate=f[6], crc=f[7], csize=f[8], usize=f[9], nlen=nlen, elen=elen,
                 clen2=clen2, disk=f[13], iattr=f[14], eattr=f[15], doff=f[16],
                 name=bytes(cd[p + 46:p + 46 + nlen]),
                 extra=cd[p + 46 + nlen:p + 46 + nlen + elen],
                 cmt=cd[p + 46 + nlen + elen:p + 46 + nlen + elen + clen2])
        # real sizes from the local header / ZIP64 extra
        lh = buf[e["doff"]:]
        l_nlen, l_elen = struct.unpack("<HH", lh[26:30])
        e["data_off"] = e["doff"] + 30 + l_nlen + l_elen
        e["extra_local"] = lh[30 + l_nlen:30 + l_nlen + l_elen]
        e["raw"] = buf[e["data_off"]:e["data_off"] + e["csize"]]
        if e["usize"] == 0xFFFFFFFF:
            q = 0
            while q + 4 <= len(e["extra"]):
                hid, hsz = struct.unpack("<HH", e["extra"][q:q + 4])
                if hid == 0x0001:
                    e["usize_real"] = struct.unpack("<Q", e["extra"][q + 4:q + 12])[0]
                q += 4 + hsz
        else:
            e["usize_real"] = e["usize"]
        e["plain"] = (zlib.decompress(e["raw"], -15)
                      if e["method"] == 8 else e["raw"])
        assert len(e["plain"]) == e["usize_real"]
        out.append(e)
        p += 46 + nlen + elen + clen2
    return out, comment, (cd_off, cd_size, n_total)


def build(src, dst):
    orig = open(src, "rb").read()
    entries, orig_comment, _ = read_entries(orig)
    print(f"  original {len(orig):,} bytes; signature comment {len(orig_comment):,} bytes")

    by_name = {e["name"]: e for e in entries}
    e_list = by_name[TARGET]
    orig_list = e_list["plain"]
    assert b"ANNEC00B000" in orig_list, "expected ANNEC00B000 in the list"
    # <MODEL><CUST>B<BUILD>: ANNE + C00 + B000 -> ANNE + C635 + B000
    # Two candidate forms, both in the <MODEL><CUST>B<BUILD> shape the existing
    # entries use: the exact build for this unit, and the base build in case the
    # check is a range (>=) rather than an equality.
    new_plain = orig_list.replace(
        b"ANNEC00B000",
        b"ANNEC635B132\nANNEC635B000")
    print(f"    list {len(orig_list)} -> {len(new_plain)} bytes")

    # keep MANIFEST.MF / CERT.SF digests consistent with the new file
    man_p = by_name[b"META-INF/MANIFEST.MF"]["plain"]
    sf_p = by_name[b"META-INF/CERT.SF"]["plain"]
    key = b"Name: " + TARGET + CRLF
    i = man_p.index(key)
    j = man_p.index(CRLF + CRLF, i)
    sec_old = man_p[i:j] + CRLF + CRLF
    old_d = sec_old.split(b"SHA1-Digest: ")[1].split(CRLF)[0]
    sec_new = sec_old.replace(old_d, b64sha1(new_plain))
    new_man = replace_one(man_p, sec_old, sec_new)
    old_sf_e = sf_p.split(b"Name: " + TARGET + CRLF)[1].split(b"SHA1-Digest: ")[1].split(CRLF)[0]
    old_sf_m = sf_p.split(b"SHA1-Digest-Manifest: ")[1].split(CRLF)[0]
    new_sf = replace_one(sf_p, old_sf_m, b64sha1(new_man))
    new_sf = replace_one(new_sf, old_sf_e, b64sha1(sec_new))
    assert len(new_man) == len(man_p) and len(new_sf) == len(sf_p)

    payloads = {TARGET: new_plain, b"META-INF/MANIFEST.MF": new_man, b"META-INF/CERT.SF": new_sf}
    max_usize = max(e["usize_real"] for e in entries)

    body = bytearray()
    central = bytearray()
    for e in entries:
        plain = payloads.get(e["name"], e["plain"])
        if e["method"] == 0:
            comp = plain
        elif e["usize_real"] == max_usize:
            # Copy the original's deflate stream byte for byte. Recompressing a
            # multi-GB payload at level 9 shrinks it by megabytes, which then does
            # not fit in the EOCD's 16-bit comment length; copying keeps the entry
            # provably identical AND leaves only the zopfli savings as slack.
            comp = e["raw"]
            print(f"    {e['name'].decode()}: copied original stream ({len(comp):,} bytes)")
        else:
            comp = raw_deflate_zopfli(plain)
            if e["name"] in payloads:
                print(f"    {e['name'].decode()}: {len(plain)} -> {len(comp)} (zopfli)")
        crc = zlib.crc32(plain) & 0xFFFFFFFF
        doff = len(body)

        use64 = len(plain) > 0xFFFFFFFE
        # The original puts the ZIP64 field in the CENTRAL directory only; its
        # local headers for the big payload carry no extra field at all. Mirror
        # that rather than "fixing" it.
        extra_lh, extra_cd = e["extra_local"], e["extra"]
        if use64:
            assert extra_cd, f"{e['name']!r} needs a ZIP64 extra in the central directory"

        usize_field = 0xFFFFFFFF if use64 else len(plain)
        body += struct.pack("<IHHHHHIIIHH", 0x04034b50, e["ver_need"], e["flags"],
                            e["method"], e["mtime"], e["mdate"], crc,
                            len(comp), usize_field, len(e["name"]),
                            len(extra_lh)) + e["name"] + extra_lh + comp

        central += struct.pack("<IHHHHHHIIIHHHHHII", 0x02014b50, e["ver_made"],
                               e["ver_need"], e["flags"], e["method"], e["mtime"],
                               e["mdate"], crc, len(comp), usize_field,
                               len(e["name"]), len(extra_cd), 0, 0,
                               e["iattr"], e["eattr"], doff) + e["name"] + extra_cd

    cd_off = len(body)
    body += central
    body += struct.pack("<IHHHHIIH", 0x06054b50, 0, 0, len(entries), len(entries),
                        len(central), cd_off, len(orig_comment) + 0)

    # now attach the original signature comment and pad to the exact original size
    room = len(orig) - len(body)
    print(f"  rebuilt {len(body):,} bytes; room for the comment: {room:,} "
          f"(need >= {len(orig_comment):,})")
    if room < len(orig_comment):
        raise SystemExit(f"  still short by {len(orig_comment) - room} bytes")
    pad = room - len(orig_comment)
    comment = orig_comment + b"\x00" * pad
    out = body[:len(body) - 2] + struct.pack("<H", len(comment)) + comment
    assert len(out) == len(orig), f"{len(out)} != {len(orig)}"
    open(dst, "wb").write(out)
    print(f"  final {len(out):,} bytes = original exactly; "
          f"comment {len(comment):,} = signature {len(orig_comment):,} + pad {pad:,}")

    # verify the rebuilt file round-trips
    got, gcomment, _ = read_entries(out)
    gp = {e["name"]: e["plain"] for e in got}
    assert gp[TARGET] == new_plain, "patched list not visible"
    assert gp[b"META-INF/MANIFEST.MF"] == new_man
    assert gp[b"UPDATE.APP"] == by_name[b"UPDATE.APP"]["plain"], "UPDATE.APP changed!"
    assert gcomment[:len(orig_comment)] == orig_comment, "signature comment not intact"
    print("  round-trip OK: patched list visible, UPDATE.APP byte-identical, "
          "signature comment intact")
    return len(orig), len(out)


for src, dst in JOBS:
    import sys
    if len(sys.argv) > 1 and sys.argv[1] not in os.path.basename(src):
        continue
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    print("=" * 72)
    print(os.path.basename(src))
    build(src, dst)
print("\ndone")
