#!/usr/bin/env python3
"""
Apply the in-place digest substitution to BOTH packages, verify each payload is
byte-identical to the original, and report.

Generalised from build_patched_v3.py so the same (now empirically verified) logic
handles the customized-data package too - it carries its own signed
SOFTWARE_VER_LIST.mbn with identical content and would fail the same check.
"""
import base64
import hashlib
import os
import shutil
import sys
import zipfile

CRLF = b"\r\n"
VERSION_ENTRY = b"SOFTWARE_VER_LIST.mbn"
ADDITIONS = """ANE-LX2J 9.1.0.132(C635E4R1P1)
9.1.0.132(C635E4R1P1)
C635E4R1P1
"""

OUTDIR = "/home/placeless/dev/p20-root/firmware/patched3"

JOBS = [
    ("/tmp/fw3/Software/dload/update_sd.zip", "update_sd.zip", "UPDATE.APP"),
    ("/tmp/fw3/Software/dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip",
     "update_sd_ANE-L22J_hw_jp.zip", "update_ANE-L22J_hw_jp.app"),
]


def b64sha1(b: bytes) -> bytes:
    return base64.b64encode(hashlib.sha1(b).digest())


def replace_one(data: bytes, old: bytes, new: bytes) -> bytes:
    assert data.count(old) == 1, f"expected 1 occurrence, found {data.count(old)}"
    return data.replace(old, new)


def patch(src: str, dst: str, payload_entry: str) -> None:
    zin = zipfile.ZipFile(src, "r")
    old_man = zin.read("META-INF/MANIFEST.MF")
    old_sf = zin.read("META-INF/CERT.SF")
    old_list = zin.read("SOFTWARE_VER_LIST.mbn")

    new_list = old_list.rstrip(b"\n") + b"\n" + ADDITIONS.encode()

    key = b"Name: " + VERSION_ENTRY + CRLF
    i = old_man.index(key)
    j = old_man.index(CRLF + CRLF, i)
    section_old = old_man[i:j] + CRLF + CRLF
    old_digest = section_old.split(b"SHA1-Digest: ")[1].split(CRLF)[0]

    new_digest = b64sha1(new_list)
    section_new = section_old.replace(old_digest, new_digest)

    new_man = replace_one(old_man, section_old, section_new)
    new_sf_entry = b64sha1(section_new)
    new_manifest_digest = b64sha1(new_man)

    old_sf_entry = old_sf.split(b"Name: " + VERSION_ENTRY + CRLF)[1].split(b"SHA1-Digest: ")[1].split(CRLF)[0]
    old_sf_manifest = old_sf.split(b"SHA1-Digest-Manifest: ")[1].split(CRLF)[0]

    new_sf = replace_one(old_sf, old_sf_manifest, new_manifest_digest)
    new_sf = replace_one(new_sf, old_sf_entry, new_sf_entry)

    assert len(new_man) == len(old_man) and len(new_sf) == len(old_sf)

    # consistency self-check
    ci = new_man.index(key)
    cj = new_man.index(CRLF + CRLF, ci)
    assert b64sha1(new_man[ci:cj] + CRLF + CRLF) == new_sf_entry
    assert b64sha1(new_man) == new_manifest_digest

    part = dst + ".part"
    with zipfile.ZipFile(part, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zout:
        for item in zin.infolist():
            payload = {
                "SOFTWARE_VER_LIST.mbn": new_list,
                "META-INF/MANIFEST.MF": new_man,
                "META-INF/CERT.SF": new_sf,
            }.get(item.filename)
            ni = zipfile.ZipInfo(item.filename, date_time=item.date_time)
            ni.compress_type = zipfile.ZIP_DEFLATED
            ni.external_attr = item.external_attr
            if payload is not None:
                zout.writestr(ni, payload)
            else:
                with zin.open(item, "r") as fi, zout.open(ni, "w", force_zip64=True) as fo:
                    shutil.copyfileobj(fi, fo, 4 * 1024 * 1024)
    os.replace(part, dst)

    print(f"  wrote {dst} ({os.path.getsize(dst):,} bytes)")
    print(f"    list  {len(old_list)} -> {len(new_list)} bytes")
    print(f"    man   {old_digest.decode()} -> {new_digest.decode()}")
    print(f"    sf    {old_sf_entry.decode()} -> {new_sf_entry.decode()}")
    print(f"    dm    {old_sf_manifest.decode()} -> {new_manifest_digest.decode()}")
    with zipfile.ZipFile(dst) as z:
        print("    zip verify:", z.testzip() or "OK")


os.makedirs(OUTDIR, exist_ok=True)
for src, name, payload_entry in JOBS:
    dst = os.path.join(OUTDIR, name)
    print(f"===== {name}")
    print(f"  payload check ({payload_entry})")
    with zipfile.ZipFile(src) as a:
        h1 = hashlib.md5(a.read(payload_entry)).hexdigest()
    patch(src, dst, payload_entry)
    with zipfile.ZipFile(dst) as b:
        h2 = hashlib.md5(b.read(payload_entry)).hexdigest()
    print(f"    payload md5 original: {h1}")
    print(f"    payload md5 patched : {h2}   {'IDENTICAL' if h1 == h2 else '*** DIFFERS ***'}")
    print()
