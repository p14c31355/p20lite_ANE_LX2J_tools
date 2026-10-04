#!/usr/bin/env python3
"""
Corrected rebuild: substitute digest VALUES in place, never re-serialise the
manifest files.

Why the previous attempt was wrong: it rebuilt MANIFEST.MF from parsed sections
and lost the blank lines that separate them, producing a malformed JAR manifest
(539 -> 525 bytes). The fix is to leave every byte alone except the 32-character
base64 digest values being replaced.

Formulas, derived empirically by matching the original package's known-good
values (see derive_digest.py):

    MANIFEST.MF entry digest = base64(sha1(<entry payload bytes>))
    CERT.SF entry digest     = base64(sha1(<manifest section bytes> + CRLF CRLF))
    SHA1-Digest-Manifest     = base64(sha1(<entire MANIFEST.MF bytes>))

Note the CERT.SF one includes the blank separator line - that is the part that is
easy to get wrong.

CERT.RSA is left untouched: it is Huawei's RSA signature over CERT.SF and cannot
be reproduced. This patch therefore only works if the updater's check is
digest-based rather than a strict signature verification.
"""
import base64
import hashlib
import os
import shutil
import zipfile

SRC = "/tmp/fw3/Software/dload/update_sd.zip"
OUTDIR = "/home/placeless/dev/p20-root/firmware/patched2"
OUT = os.path.join(OUTDIR, "update_sd.zip")

ADDITIONS = """ANE-LX2J 9.1.0.132(C635E4R1P1)
9.1.0.132(C635E4R1P1)
C635E4R1P1
"""

CRLF = b"\r\n"
VERSION_ENTRY = b"SOFTWARE_VER_LIST.mbn"


def b64sha1(b: bytes) -> bytes:
    return base64.b64encode(hashlib.sha1(b).digest())


def replace_one(data: bytes, old: bytes, new: bytes) -> bytes:
    assert data.count(old) == 1, f"expected exactly one occurrence of {old!r}, found {data.count(old)}"
    return data.replace(old, new)


os.makedirs(OUTDIR, exist_ok=True)
zin = zipfile.ZipFile(SRC, "r")

old_man = zin.read("META-INF/MANIFEST.MF")
old_sf = zin.read("META-INF/CERT.SF")
old_list = zin.read("SOFTWARE_VER_LIST.mbn")

# --- new payload for SOFTWARE_VER_LIST.mbn
new_list = old_list.rstrip(b"\n") + b"\n" + ADDITIONS.encode()

# --- locate the entry's section inside MANIFEST.MF
key = b"Name: " + VERSION_ENTRY + CRLF
i = old_man.index(key)
j = old_man.index(CRLF + CRLF, i)          # end of that section, before the blank line
section_old = old_man[i:j] + CRLF + CRLF   # section as hashed by CERT.SF
old_digest = section_old.split(b"SHA1-Digest: ")[1].split(CRLF)[0]

# --- new digests
new_digest = b64sha1(new_list)
section_new = section_old.replace(old_digest, new_digest)
assert len(section_new) == len(section_old), "digest length must not change"

new_man = replace_one(old_man, section_old, section_new)   # in place, byte-for-byte elsewhere
new_sf_entry_digest = b64sha1(section_new)
new_manifest_digest = b64sha1(new_man)

old_sf_entry = old_sf.split(b"Name: " + VERSION_ENTRY + CRLF)[1].split(b"SHA1-Digest: ")[1].split(CRLF)[0]
old_sf_manifest = old_sf.split(b"SHA1-Digest-Manifest: ")[1].split(CRLF)[0]

new_sf = replace_one(old_sf, old_sf_manifest, new_manifest_digest)
new_sf = replace_one(new_sf, old_sf_entry, new_sf_entry_digest)

print("SOFTWARE_VER_LIST.mbn :", len(old_list), "->", len(new_list), "bytes")
print("  MANIFEST digest   :", old_digest.decode(), "->", new_digest.decode())
print("  CERT.SF  digest   :", old_sf_entry.decode(), "->", new_sf_entry_digest.decode())
print("  Digest-Manifest   :", old_sf_manifest.decode(), "->", new_manifest_digest.decode())
print("MANIFEST.MF size :", len(old_man), "->", len(new_man), "(must be equal)")
print("CERT.SF size     :", len(old_sf), "->", len(new_sf), "(must be equal)")

# --- self-check: recompute everything from the new bytes and confirm consistency
chk_key = b"Name: " + VERSION_ENTRY + CRLF
ci = new_man.index(chk_key)
cj = new_man.index(CRLF + CRLF, ci)
chk_section = new_man[ci:cj] + CRLF + CRLF
assert b"SHA1-Digest: " + b64sha1(new_list) in new_man, "manifest entry digest inconsistent"
assert b64sha1(chk_section) == new_sf_entry_digest, "CERT.SF entry digest inconsistent"
assert b64sha1(new_man) == new_manifest_digest, "Digest-Manifest inconsistent"
print("self-check: all three digests recompute consistently")

part = OUT + ".part"
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

os.replace(part, OUT)
print(f"\nwrote {OUT} ({os.path.getsize(OUT):,} bytes)")
with zipfile.ZipFile(OUT) as z:
    print("zip verify:", z.testzip() or "OK")
