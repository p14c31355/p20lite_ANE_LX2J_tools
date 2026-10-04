#!/usr/bin/env python3
"""
Sanity-check the rebuilt manifest files before they go anywhere near the device.
A malformed JAR manifest is a guaranteed failure, so dump both versions and diff
them entry by entry.
"""
import zipfile

A = "/tmp/fw3/Software/dload/update_sd.zip"
B = "/home/placeless/dev/p20-root/firmware/patched2/update_sd.zip"

for label, path in (("ORIGINAL", A), ("PATCHED", B)):
    print("=" * 70)
    print(f"{label}: {path}")
    with zipfile.ZipFile(path) as z:
        for name in ("META-INF/MANIFEST.MF", "META-INF/CERT.SF", "SOFTWARE_VER_LIST.mbn"):
            data = z.read(name)
            print(f"\n--- {name}  ({len(data)} bytes)")
            print(repr(data.decode("utf-8", "replace"))[:1200])
