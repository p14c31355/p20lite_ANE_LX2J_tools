#!/usr/bin/env python3
"""
Verify the same-size build of update_sd.zip:
  1. total byte count identical to the original
  2. the patched version list is what the main view sees
  3. UPDATE.APP's bytes are untouched
  4. the original signature comment is present verbatim at the start of the comment
  5. MANIFEST.MF / CERT.SF digests recompute consistently
"""
import base64
import hashlib
import struct
import zipfile
import zlib

NEW = "/home/placeless/dev/p20-root/firmware/samesize/update_sd.zip"
ORIG = "/tmp/fw3/Software/dload/update_sd.zip"
EOCD_SIG = b"PK\x05\x06"
CRLF = b"\r\n"
TARGET = b"SOFTWARE_VER_LIST.mbn"

for label, p in (("original", ORIG), ("same-size build", NEW)):
    b = open(p, "rb").read()
    print(f"{label:16}: {len(b):,} bytes")

a = open(ORIG, "rb").read()
n = open(NEW, "rb").read()
print(f"\nsame length: {len(a) == len(n)}")
if len(a) != len(n):
    raise SystemExit("lengths differ - stop")

def eocd(buf):
    best = None
    i = buf.find(EOCD_SIG)
    while i != -1:
        if i + 22 <= len(buf):
            cl = struct.unpack("<H", buf[i + 20:i + 22])[0]
            if i + 22 + cl == len(buf):
                best = (i, cl)
        i = buf.find(EOCD_SIG, i + 1)
    return best

ea, ca = eocd(a)
en, cn = eocd(n)
print(f"original EOCD @{ea:#x} comment {ca:,}   new EOCD @{en:#x} comment {cn:,}")
print(f"comment starts with the original signature: {n[en+22:en+22+ca] == a[ea+22:ea+22+ca]}")

print("\n=== entries in the new build ===")
with zipfile.ZipFile(NEW) as z:
    for i in z.infolist():
        print(f"   {i.file_size:>12} {i.compress_size:>12} {i.filename}")
    lst = z.read("SOFTWARE_VER_LIST.mbn")
    print("\nSOFTWARE_VER_LIST.mbn as the extractor sees it:")
    print("   " + repr(lst))

    # digest consistency
    man = z.read("META-INF/MANIFEST.MF")
    sf = z.read("META-INF/CERT.SF")
    key = b"Name: " + TARGET + CRLF
    i = man.index(key)
    j = man.index(CRLF + CRLF, i)
    sec = man[i:j] + CRLF + CRLF
    d1 = base64.b64encode(hashlib.sha1(lst).digest())
    d2 = base64.b64encode(hashlib.sha1(sec).digest())
    d3 = base64.b64encode(hashlib.sha1(man).digest())
    print(f"   manifest entry digest correct : {b'SHA1-Digest: ' + d1 in man}")
    print(f"   cert.sf entry digest correct  : {d2 in sf}")
    print(f"   cert.sf manifest digest       : {d3 in sf}")

    # UPDATE.APP must be byte-identical
    h_new = hashlib.md5(z.read("UPDATE.APP")).hexdigest()
with zipfile.ZipFile(ORIG) as z:
    h_old = hashlib.md5(z.read("UPDATE.APP")).hexdigest()
print(f"\nUPDATE.APP md5 original : {h_old}")
print(f"UPDATE.APP md5 new      : {h_new}   {'IDENTICAL' if h_old == h_new else '*** DIFFERS ***'}")
