#!/usr/bin/env python3
"""
Same patch, applied to the customized-data package.

The inner package carries its own SOFTWARE_VER_LIST.mbn with identical content
(ANNEC00B000 / ANE-BD 1.0.0.1 / ANE-BD 1.0.0.999), so it would fail the same
sec_dld_main_version_check. Patch it in the same cycle to avoid a wasted
device round-trip.

Its payload entry is update_ANE-L22J_hw_jp.app and is copied through untouched.
"""
import os
import shutil
import zipfile

SRC = "/tmp/fw3/Software/dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip"
OUTDIR = "/home/placeless/dev/p20-root/firmware/patched"
OUT = os.path.join(OUTDIR, "update_sd_ANE-L22J_hw_jp.zip")

ADDITIONS = """ANE-LX2J 9.1.0.132(C635E4R1P1)
9.1.0.132(C635E4R1P1)
C635E4R1P1
"""

os.makedirs(OUTDIR, exist_ok=True)
zin = zipfile.ZipFile(SRC, "r")
part = OUT + ".part"
print("building", OUT)

with zipfile.ZipFile(part, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zout:
    for item in zin.infolist():
        if item.filename == "SOFTWARE_VER_LIST.mbn":
            old = zin.read(item.filename).decode("utf-8", "replace")
            new = old.rstrip("\n") + "\n" + ADDITIONS
            print(f"  {item.filename}: {len(old)} -> {len(new)} bytes")
            ni = zipfile.ZipInfo(item.filename, date_time=item.date_time)
            ni.compress_type = zipfile.ZIP_DEFLATED
            zout.writestr(ni, new.encode())
            continue
        ni = zipfile.ZipInfo(item.filename, date_time=item.date_time)
        ni.compress_type = zipfile.ZIP_DEFLATED
        ni.external_attr = item.external_attr
        with zin.open(item, "r") as fi, zout.open(ni, "w", force_zip64=True) as fo:
            shutil.copyfileobj(fi, fo, 4 * 1024 * 1024)

os.replace(part, OUT)
print(f"wrote {OUT} ({os.path.getsize(OUT):,} bytes)")

with zipfile.ZipFile(OUT) as z:
    print("verify:", z.testzip() or "OK")
    print("--- SOFTWARE_VER_LIST.mbn now:")
    print(z.read("SOFTWARE_VER_LIST.mbn").decode())
