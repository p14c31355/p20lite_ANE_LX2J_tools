#!/usr/bin/env python3
"""
Attempt 4: keep the file size EXACTLY equal to the original.

Why the size may matter: update-binary contains sec_dld_crc_verify and
update_comm_write_crc, and every attempt so far changed the total file size:

    original            2,064,931,292
    attempt 1 and 2     2,064,929,769   (-1,523)
    attempt 3 (EOCD)    2,064,932,128   (+836)

If any check covers the whole file - CRC, length, or a hash over the container -
all three were doomed regardless of their content.

This build instead:
  * patches SOFTWARE_VER_LIST.mbn and keeps MANIFEST.MF / CERT.SF consistent,
  * compresses at level 9 so the result comes out SMALLER than the original,
  * re-attaches the original signature comment verbatim,
  * pads the comment so the total byte count matches the original exactly.

The padding sits after the signature inside the comment field, so the bytes the
signature would cover are untouched by it.
"""
import base64
import hashlib
import os
import shutil
import struct
import zipfile

CRLF = b"\r\n"
TARGET = b"SOFTWARE_VER_LIST.mbn"
EOCD_SIG = b"PK\x05\x06"
EOCD_FMT = "<IHHHHIIH"
ADDITION = "ANE-LX2J 9.1.0.132(C635E4R1P1)\n"     # one line; every byte counts

JOBS = [
    ("/tmp/fw3/Software/dload/update_sd.zip",
     "/home/placeless/dev/p20-root/firmware/samesize/update_sd.zip"),
    ("/tmp/fw3/Software/dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip",
     "/home/placeless/dev/p20-root/firmware/samesize/update_sd_ANE-L22J_hw_jp.zip"),
]


def find_eocd(buf):
    """The genuine EOCD: the candidate whose comment length accounts for the file."""
    best = None
    pos = buf.find(EOCD_SIG)
    while pos != -1:
        if pos + 22 <= len(buf):
            clen = struct.unpack("<H", buf[pos + 20:pos + 22])[0]
            if pos + 22 + clen == len(buf):
                best = pos
        pos = buf.find(EOCD_SIG, pos + 1)
    return best


def b64sha1(b: bytes) -> bytes:
    return base64.b64encode(hashlib.sha1(b).digest())


def replace_one(data: bytes, old: bytes, new: bytes) -> bytes:
    assert data.count(old) == 1, f"expected 1 occurrence of {old!r}, got {data.count(old)}"
    return data.replace(old, new)


def build(src, dst):
    orig = open(src, "rb").read()
    eocd = find_eocd(orig)
    assert eocd is not None
    clen = struct.unpack("<H", orig[eocd + 20:eocd + 22])[0]
    orig_comment = orig[eocd + 22:eocd + 22 + clen]
    print(f"  original      : {len(orig):,} bytes, comment {clen} bytes "
          f"(starts {orig_comment[:18]!r})")

    zin = zipfile.ZipFile(src, "r")
    old_man = zin.read("META-INF/MANIFEST.MF")
    old_sf = zin.read("META-INF/CERT.SF")

    old_list = zin.read("SOFTWARE_VER_LIST.mbn")
    new_list = old_list.rstrip(b"\n") + b"\n" + ADDITION.encode()

    key = b"Name: " + TARGET + CRLF
    i = old_man.index(key)
    j = old_man.index(CRLF + CRLF, i)
    section_old = old_man[i:j] + CRLF + CRLF
    old_digest = section_old.split(b"SHA1-Digest: ")[1].split(CRLF)[0]
    new_digest = b64sha1(new_list)
    section_new = section_old.replace(old_digest, new_digest)

    new_man = replace_one(old_man, section_old, section_new)
    new_sf_entry = b64sha1(section_new)
    new_manifest_digest = b64sha1(new_man)

    old_sf_entry = old_sf.split(b"Name: " + TARGET + CRLF)[1].split(b"SHA1-Digest: ")[1].split(CRLF)[0]
    old_sf_manifest = old_sf.split(b"SHA1-Digest-Manifest: ")[1].split(CRLF)[0]
    new_sf = replace_one(old_sf, old_sf_manifest, new_manifest_digest)
    new_sf = replace_one(new_sf, old_sf_entry, new_sf_entry)
    assert len(new_man) == len(old_man) and len(new_sf) == len(old_sf)

    # rebuild at maximum compression, mimicking the ORIGINAL per-entry method.
    # The original stores the three tiny files uncompressed; deflating them would
    # add bytes rather than save them, which is what put us 49 bytes over budget.
    part = dst + ".part"
    with zipfile.ZipFile(part, "w", zipfile.ZIP_DEFLATED, allowZip64=True,
                         compresslevel=9) as zout:
        for item in zin.infolist():
            payload = {
                "SOFTWARE_VER_LIST.mbn": new_list,
                "META-INF/MANIFEST.MF": new_man,
                "META-INF/CERT.SF": new_sf,
            }.get(item.filename)
            ni = zipfile.ZipInfo(item.filename, date_time=item.date_time)
            ni.compress_type = item.compress_type      # keep the original's method
            ni.external_attr = item.external_attr
            if payload is not None:
                zout.writestr(ni, payload)
            else:
                with zin.open(item, "r") as fi, zout.open(ni, "w", force_zip64=True) as fo:
                    shutil.copyfileobj(fi, fo, 4 * 1024 * 1024)

    body = open(part, "rb").read()
    print(f"  rebuilt       : {len(body):,} bytes (level 9, no comment)")

    need = len(orig) - len(body)
    print(f"  room for comment: {need:,} bytes; original signature is {len(orig_comment):,}")
    if need < len(orig_comment):
        raise SystemExit(f"  NOT ENOUGH ROOM: need {len(orig_comment)}, have {need} - "
                         f"trim the addition or compress harder")
    if need > 0xFFFF:
        raise SystemExit("  comment field would overflow 16 bits")

    # attach the original signature verbatim, then pad to the exact original size
    pad = need - len(orig_comment)
    comment = orig_comment + (b"\x00" * pad)
    pos = find_eocd(body)
    assert pos is not None and body[pos + 22:] == b"", "unexpected existing comment"
    out = body[:pos + 20] + struct.pack("<H", len(comment)) + body[pos + 22:] + comment
    assert len(out) == len(orig), f"{len(out)} != {len(orig)}"
    open(dst, "wb").write(out)
    print(f"  final         : {len(out):,} bytes  (exact match: {len(out) == len(orig)})")
    print(f"                  comment {len(comment):,} = signature {len(orig_comment):,} + pad {pad:,}")

    # sanity: the main view must show the patched list, digests consistent
    with zipfile.ZipFile(dst) as z:
        got = z.read("SOFTWARE_VER_LIST.mbn")
        assert got == new_list, "main view does not show the patched list"
        man = z.read("META-INF/MANIFEST.MF")
        sf = z.read("META-INF/CERT.SF")
        k = man.index(key)
        j2 = man.index(CRLF + CRLF, k)
        sec = man[k:j2] + CRLF + CRLF
        assert b64sha1(new_list) in man
        assert b64sha1(sec) in sf
        assert b64sha1(man) in sf
    print("  digests and patched list verified in the main view")
    os.remove(part)
    return len(orig), len(out)


for src, dst in JOBS:
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    print("=" * 72)
    print(os.path.basename(src))
    build(src, dst)
print("\ndone")
