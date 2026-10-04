#!/usr/bin/env python3
"""
Derive the exact digest formula empirically instead of guessing.

The original package gives us known-good values to match:
    MANIFEST.MF entry for SOFTWARE_VER_LIST.mbn : SHA1-Digest: noBWdNWVlFXHy7qpSjppvffbICY=
    CERT.SF     entry for SOFTWARE_VER_LIST.mbn : SHA1-Digest: UEvNLxkl7DkT8pFUCQOQtq9NcUY=
    CERT.SF                                     : SHA1-Digest-Manifest: P9gv8CmUZ2JaSxALtz1XHDK9cZk=

Whichever byte string hashes to each of those tells us exactly what to feed in.
"""
import base64
import hashlib
import zipfile

A = "/tmp/fw3/Software/dload/update_sd.zip"
TARGET_MAN_ENTRY = "noBWdNWVlFXHy7qpSjppvffbICY="
TARGET_SF_ENTRY = "UEvNLxkl7DkT8pFUCQOQtq9NcUY="
TARGET_SF_MANIFEST = "P9gv8CmUZ2JaSxALtz1XHDK9cZk="


def b64(b: bytes) -> str:
    return base64.b64encode(hashlib.sha1(b).digest()).decode()


z = zipfile.ZipFile(A)
man = z.read("META-INF/MANIFEST.MF")
sf = z.read("META-INF/CERT.SF")
listb = z.read("SOFTWARE_VER_LIST.mbn")

print("########## 1. what hashes to the MANIFEST entry digest?")
print("   target:", TARGET_MAN_ENTRY)
cands = {
    "sha1(SOFTWARE_VER_LIST.mbn raw)": listb,
    "sha1(zip entry bytes)": z.read("SOFTWARE_VER_LIST.mbn"),
}
for k, v in cands.items():
    print(f"   {k:44} {b64(v)}   {'<== MATCH' if b64(v) == TARGET_MAN_ENTRY else ''}")

print()
print("########## 2. what hashes to the CERT.SF manifest-entry digest?")
print("   target:", TARGET_SF_ENTRY)
# Reconstruct candidate manifest sections exactly.
name = "META-INF/MANIFEST.MF"
man_sections = {}
for chunk in man.split(b"\r\n\r\n"):
    if b"Name:" in chunk:
        nm = chunk.split(b"\r\n")[0][5:].strip().decode()
        man_sections[nm] = chunk
print("   manifest sections found:", list(man_sections))
for nm, chunk in man_sections.items():
    variants = {
        "with trailing CRLF": chunk + b"\r\n",
        "bare (no trailing)": chunk,
        "with blank line": chunk + b"\r\n\r\n",
        "LF-normalised + CRLF": chunk.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n") + b"\r\n",
    }
    for label, v in variants.items():
        h = b64(v)
        mark = "   <== MATCH" if h == TARGET_SF_ENTRY and nm == "SOFTWARE_VER_LIST.mbn" else ""
        if nm == "SOFTWARE_VER_LIST.mbn" or mark:
            print(f"   [{nm}] {label:24} {h}{mark}")

print()
print("########## 3. what hashes to SHA1-Digest-Manifest?")
print("   target:", TARGET_SF_MANIFEST)
for label, v in {
    "whole MANIFEST.MF": man,
    "MANIFEST.MF minus trailing CRLF": man[:-2],
    "MANIFEST.MF normalised": man.replace(b"\r\n", b"\n"),
}.items():
    h = b64(v)
    print(f"   {label:36} {h}   {'<== MATCH' if h == TARGET_SF_MANIFEST else ''}")
