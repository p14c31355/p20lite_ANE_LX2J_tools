#!/usr/bin/env python3
"""
Second attempt at the version wall.

What we know for certain (measured, not inferred):
  * The unmodified package is refused by sec_dld_main_version_check, which
    compares SOFTWARE_VER_LIST.mbn against the device's ro.build.display.id.
  * Appending this device's version to that list gets PAST that check: the updater
    proceeded into the write phase (progress bar reached 5%) instead of showing
    "Software install failed!".
  * But it then aborted silently at 5% and rebooted. No error screen - which is
    what an assert() failure looks like, and the updater-script's only statement is
        assert(compress_sd_update_from_zip("UPDATE.APP"));
  * SOFTWARE_VER_LIST.mbn IS covered by the package's JAR signature
    (it appears in both MANIFEST.MF and CERT.SF).

Crucially: the version check READ our edited file and passed, so the signature
was not verified before it. That leaves room: make the digests self-consistent
with the edited file and see whether the later verification is digest-only
rather than a strict RSA check.

Updated here:
  MANIFEST.MF : SHA1-Digest of SOFTWARE_VER_LIST.mbn
  CERT.SF     : SHA1-Digest of that manifest section, and SHA1-Digest-Manifest
CERT.RSA is deliberately left alone - it is Huawei's signature over CERT.SF and
we cannot reproduce it. If verification is strict, this fails; if it is
digest-based, it passes.

Note the digests are BASE64 OF SHA1, not hex - "SHA1-Digest" in a JAR is the
base64 form, unlike the hex used by sha1sum.
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

CRLF = "\r\n"


def b64sha1(data: bytes) -> str:
    return base64.b64encode(hashlib.sha1(data).digest()).decode()


def split_sections(text: str):
    """Split a JAR manifest/.SF into (preamble, [(name, section_text)]) keeping
    the exact original bytes of each section, since the .SF digest is taken over
    the section bytes as they appear in the manifest."""
    text = text.replace("\r\n", "\n")
    parts = text.split("\n\n")
    preamble = parts[0]
    sections = []
    for chunk in parts[1:]:
        if not chunk.strip():
            continue
        name = None
        for line in chunk.split("\n"):
            if line.startswith("Name:"):
                name = line[5:].strip()
                break
        sections.append((name, chunk))
    return preamble, sections


os.makedirs(OUTDIR, exist_ok=True)
zin = zipfile.ZipFile(SRC, "r")

entries = {i.filename: i for i in zin.infolist()}
n2 = {i.filename: i for i in zin.infolist()}

# ---- 1. build the new SOFTWARE_VER_LIST.mbn
old_list = zin.read("SOFTWARE_VER_LIST.mbn").decode("utf-8", "replace")
new_list = old_list.rstrip("\n") + "\n" + ADDITIONS
new_list_bytes = new_list.encode()
print("SOFTWARE_VER_LIST.mbn:", len(old_list), "->", len(new_list_bytes), "bytes")
print("  new sha1(b64) =", b64sha1(new_list_bytes))

# ---- 2. rewrite MANIFEST.MF
man_text = zin.read("META-INF/MANIFEST.MF").decode("utf-8")
preamble, sections = split_sections(man_text)
out_man_parts = [preamble.replace("\n", CRLF)]
new_sections_text = {}
for name, chunk in sections:
    if name == "SOFTWARE_VER_LIST.mbn":
        lines = []
        for line in chunk.split("\n"):
            if line.startswith("SHA1-Digest:"):
                lines.append("SHA1-Digest: " + b64sha1(new_list_bytes))
            else:
                lines.append(line)
        chunk = "\n".join(lines)
    new_sections_text[name] = chunk
    out_man_parts.append(chunk.replace("\n", CRLF))
new_manifest = CRLF.join(out_man_parts) + CRLF
print("MANIFEST.MF:", len(man_text), "->", len(new_manifest), "bytes")

# ---- 3. rewrite CERT.SF
sf_text = zin.read("META-INF/CERT.SF").decode("utf-8")
sf_pre, sf_sections = split_sections(sf_text)
out_sf_parts = []
for line in sf_pre.split("\n"):
    if line.startswith("SHA1-Digest-Manifest:"):
        line = "SHA1-Digest-Manifest: " + b64sha1(new_manifest.encode())
    out_sf_parts.append(line)
out_sf = CRLF.join(out_sf_parts)
for name, chunk in sf_sections:
    if name == "SOFTWARE_VER_LIST.mbn":
        sec_bytes = new_sections_text["SOFTWARE_VER_LIST.mbn"].replace("\n", CRLF)
        if not sec_bytes.endswith(CRLF):
            sec_bytes += CRLF
        d = b64sha1(sec_bytes.encode())
        lines = []
        for line in chunk.split("\n"):
            if line.startswith("SHA1-Digest:"):
                lines.append("SHA1-Digest: " + d)
            else:
                lines.append(line)
        chunk = "\n".join(lines)
    out_sf += CRLF + CRLF + chunk.replace("\n", CRLF)
out_sf += CRLF
print("CERT.SF:", len(sf_text), "->", len(out_sf), "bytes")

# ---- 4. rebuild the zip
part = OUT + ".part"
with zipfile.ZipFile(part, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zout:
    for item in zin.infolist():
        payload = None
        if item.filename == "SOFTWARE_VER_LIST.mbn":
            payload = new_list_bytes
        elif item.filename == "META-INF/MANIFEST.MF":
            payload = new_manifest.encode()
        elif item.filename == "META-INF/CERT.SF":
            payload = out_sf.encode()

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
    print("verify:", z.testzip() or "OK")
