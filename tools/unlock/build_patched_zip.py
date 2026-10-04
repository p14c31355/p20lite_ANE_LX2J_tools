#!/usr/bin/env python3
"""
Rebuild update_sd.zip with an expanded SOFTWARE_VER_LIST.mbn.

Why this is the right lever (evidence from `strings update-binary`, the program
that prints the failure the device showed):

    sec_dld_main_version_check
    "current version in oeminfo is %s"
    "ro.build.display.id" / "ro.build.display.id is %s"
    "version check fail,exit update!"
    "SOFTWARE_VER_LIST.mbn"

The package currently lists only factory-state identifiers:

    ANNEC00B000
    ANE-BD 1.0.0.1
    ANE-BD 1.0.0.999

Our unit reports ro.build.display.id = ANE-LX2J 9.1.0.132(C635E4R1P1), which is
absent, hence "Incompatibility with current version".

UPDATE.APP is copied through byte-for-byte, so the firmware image itself keeps
Huawei's own signature. Only the outer JAR signature is invalidated.
"""
import os
import shutil
import zipfile

SRC = "/tmp/fw3/Software/dload/update_sd.zip"
OUTDIR = "/home/placeless/dev/p20-root/firmware/patched"
OUT = os.path.join(OUTDIR, "update_sd.zip")

ADDITIONS = """ANE-LX2J 9.1.0.132(C635E4R1P1)
9.1.0.132(C635E4R1P1)
C635E4R1P1
"""

os.makedirs(OUTDIR, exist_ok=True)

zin = zipfile.ZipFile(SRC, "r")
print("source entries:")
for i in zin.infolist():
    print(f"  {i.file_size:>12} {i.compress_size:>12}  {i.filename}")

print("\nbuilding", OUT)
part = OUT + ".part"

with zipfile.ZipFile(part, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zout:
    for item in zin.infolist():
        if item.filename == "SOFTWARE_VER_LIST.mbn":
            old = zin.read(item.filename).decode("utf-8", "replace")
            new = old.rstrip("\n") + "\n" + ADDITIONS
            print(f"\n  {item.filename}:  {len(old)} -> {len(new)} bytes")
            print("    " + new.replace("\n", "\n    ").rstrip())
            ni = zipfile.ZipInfo(item.filename, date_time=item.date_time)
            ni.compress_type = zipfile.ZIP_DEFLATED
            zout.writestr(ni, new.encode())
            continue

        # Stream every other entry (UPDATE.APP included) without ever holding it
        # in memory or on disk uncompressed.
        ni = zipfile.ZipInfo(item.filename, date_time=item.date_time)
        ni.compress_type = zipfile.ZIP_DEFLATED
        ni.external_attr = item.external_attr
        with zin.open(item, "r") as fi, zout.open(ni, "w", force_zip64=True) as fo:
            shutil.copyfileobj(fi, fo, 4 * 1024 * 1024)

os.replace(part, OUT)
size = os.path.getsize(OUT)
print(f"\nwrote {OUT}  ({size:,} bytes)")

# Verify the result is readable and the entry landed.
with zipfile.ZipFile(OUT) as z:
    print("verify:", z.testzip() or "OK")
    for i in z.infolist():
        if i.filename == "SOFTWARE_VER_LIST.mbn":
            print("--- SOFTWARE_VER_LIST.mbn now:")
            print(z.read(i.filename).decode())
