#!/usr/bin/env python3
"""
Two things:

1. Dump the strings AROUND the key literals in sbin/recovery, with offsets, so the
   comparison logic and the expected formats become visible. Flat string lists hide
   this; offsets preserve the neighbours that the compiler emitted together.

2. Read the small files out of the recovery's own embedded update package - they
   show exactly what a package of this era carries (notably
   META-INF/com/android/metadata, which our TA build lacks entirely).
"""
import re
import zipfile

REC = "/tmp/recov/recovery.bin"
EMB = "/tmp/recov/update_huawei_dload.zip"

blob = open(REC, "rb").read()
strs = [(m.start(), m.group().decode("ascii", "replace"))
        for m in re.finditer(rb"[ -~]{4,120}", blob)]

for needle in ("SOFTWARE_VER_LIST.mbn", "VERSION.mbn", "skipauth_pkg.tag",
               "/data/VERSION.mbn", "update.auth.prop", "compatibility.zip"):
    print("=" * 78)
    print(f"##### {needle}")
    hits = [i for i, (o, s) in enumerate(strs) if needle in s]
    for h in hits[:3]:
        lo, hi = max(0, h - 12), min(len(strs), h + 13)
        for k in range(lo, hi):
            mark = "  <<<" if k == h else ""
            print(f"   {strs[k][0]:>9}  {strs[k][1][:100]}{mark}")
        print("   " + "-" * 70)

print("=" * 78)
print("##### embedded package: small text entries")
with zipfile.ZipFile(EMB) as z:
    for nm in ("META-INF/com/android/metadata", "META-INF/MANIFEST.MF",
               "META-INF/CERT.SF", "META-INF/com/google/android/updater-script"):
        try:
            d = z.read(nm)
            print(f"\n--- {nm} ({len(d)} bytes)")
            print(d.decode("utf-8", "replace")[:1500])
        except KeyError:
            print(f"\n--- {nm}: absent")
