#!/usr/bin/env python3
"""
Verify both same-size builds: identical byte count, patched list visible,
big payload untouched, original signature comment preserved, digests consistent.
"""
import base64
import hashlib
import struct
import sys
import zipfile

EOCD_SIG = b"PK\x05\x06"
CRLF = b"\r\n"
TARGET = b"SOFTWARE_VER_LIST.mbn"

JOBS = [
    ("/tmp/fw3/Software/dload/update_sd.zip",
     "/home/placeless/dev/p20-root/firmware/dl110/update_sd.zip", "UPDATE.APP"),
    ("/tmp/fw3/Software/dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip",
     "/home/placeless/dev/p20-root/firmware/dl110/update_sd_ANE-L22J_hw_jp.zip",
     "update_ANE-L22J_hw_jp.app"),
]


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


ok_all = True
for orig_p, new_p, payload in JOBS:
    print("=" * 72)
    print(new_p.split("/")[-1])
    a = open(orig_p, "rb").read()
    n = open(new_p, "rb").read()

    same_len = len(a) == len(n)
    print(f"  original {len(a):,}   build {len(n):,}   identical size: {same_len}")
    ok_all &= same_len

    ea, ca = eocd(a)
    en, cn = eocd(n)
    sig_ok = n[en + 22:en + 22 + ca] == a[ea + 22:ea + 22 + ca]
    print(f"  comment {ca:,} -> {cn:,}; original signature preserved as prefix: {sig_ok}")
    ok_all &= sig_ok

    with zipfile.ZipFile(new_p) as z:
        names = z.namelist()
        lst = z.read("SOFTWARE_VER_LIST.mbn")
        man = z.read("META-INF/MANIFEST.MF")
        sf = z.read("META-INF/CERT.SF")

        key = b"Name: " + TARGET + CRLF
        i = man.index(key)
        j = man.index(CRLF + CRLF, i)
        sec = man[i:j] + CRLF + CRLF
        d1 = base64.b64encode(hashlib.sha1(lst).digest())
        d2 = base64.b64encode(hashlib.sha1(sec).digest())
        d3 = base64.b64encode(hashlib.sha1(man).digest())
        dig_ok = (b"SHA1-Digest: " + d1 in man) and (d2 in sf) and (d3 in sf)

        new_md5 = hashlib.md5(z.read(payload)).hexdigest()
        missing = [x for x in ("META-INF/CERT.RSA", "SD_update.tag", "full_mainpkg.tag",
                               "META-INF/com/google/android/update-binary",
                               "META-INF/com/android/otacert", TARGET.decode(), payload)
                   if x not in names]
    with zipfile.ZipFile(orig_p) as z:
        old_md5 = hashlib.md5(z.read(payload)).hexdigest()

    print(f"  SOFTWARE_VER_LIST.mbn: {len(lst)} bytes -> {lst.splitlines()[-1]!r}")
    print(f"  digests consistent: {dig_ok}")
    print(f"  entries present: {not missing}" + (f"  MISSING {missing}" if missing else ""))
    print(f"  {payload}: {'IDENTICAL' if old_md5 == new_md5 else '*** DIFFERS ***'}")
    ok_all &= dig_ok and not missing and (old_md5 == new_md5)

print("\n" + ("ALL CHECKS PASSED" if ok_all else "SOME CHECKS FAILED"))
sys.exit(0 if ok_all else 1)
