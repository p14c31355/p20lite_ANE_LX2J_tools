#!/usr/bin/env python3
"""
Find out whether a COMPLETE dload package for ANNE contains the files our TA build
lacks: UPT_VER.tag, sec_xloader_header, packageinfo.mbn, BOARDID_LIST.mbn,
VERSION.mbn, hotakey_sign_version.tag.

Method: the ZIP central directory sits at the END of the archive, and it lists every
entry name. So a plain HTTP range request for the last megabyte of any dload zip
answering the question - no need to download 2.5 GB.

Try several mirrors and report which ones allow unauthenticated range reads.
"""
import struct
import subprocess

CANDIDATES = [
    "https://service-gsm.net/Huawei/ANE-LX1/Anne-L01-L21%209.1.0.132(C432E5R1P7T8)%20Firmware%209.0.0%20r3%20EMUI9.1.0%2005014YWN%2005014YXX.zip",
]

WANTED = [b"UPT_VER.tag", b"sec_xloader_header", b"packageinfo.mbn", b"BOARDID_LIST.mbn",
          b"VERSION.mbn", b"hotakey_sign_version.tag", b"skipauth_pkg.tag",
          b"SD_update.tag", b"OTA_update.tag", b"full_mainpkg.tag", b"SOFTWARE_VER_LIST.mbn"]

for url in CANDIDATES:
    print("=" * 78)
    print(url[:120])
    # HEAD first, to learn whether range reads are possible at all
    head = subprocess.run(["curl", "-sIL", "--max-time", "45", url],
                          capture_output=True, text=True).stdout
    length = None
    for line in head.splitlines():
        if line.lower().startswith(("content-length:", "content-range:")):
            print("   ", line.strip())
            try:
                length = int(line.split("/")[-1].strip())
            except ValueError:
                pass
    if length is None:
        print("    no content-length / not readable")
        continue

    # read the last 1 MiB
    start = max(0, length - (1 << 20))
    r = subprocess.run(["curl", "-sL", "--max-time", "120", "-r", f"{start}-",
                        url], capture_output=True)
    blob = r.stdout
    print(f"    fetched {len(blob):,} bytes from offset {start:,} of {length:,}")
    if len(blob) < 100:
        print("    (empty - probably needs auth)")
        continue

    # locate EOCD in this tail
    EOCD = b"PK\x05\x06"
    idx = blob.rfind(EOCD)
    names = []
    if idx != -1:
        n_total, cd_size, cd_off = struct.unpack("<HII", blob[idx + 10:idx + 20])
        print(f"    EOCD found; entries={n_total} cd_off={cd_off:#x} cd_size={cd_size}")
        # the CD itself may be inside our window
        rel = cd_off - start
        if 0 <= rel < len(blob):
            cd = blob[rel:rel + cd_size]
            p = 0
            while p + 46 <= len(cd):
                f = struct.unpack("<IHHHHHHIIIHHHHHII", cd[p:p + 46])
                nlen = f[10]
                name = cd[p + 46:p + 46 + nlen]
                names.append(name)
                p += 46 + nlen + f[11] + f[12]
        else:
            print("    central directory is outside the fetched window - widen it")
    print(f"    entry names found ({len(names)}):")
    for n in names:
        mark = "  <== WE LACK THIS" if n in WANTED[:6] else ""
        print(f"       {n.decode('utf-8', 'replace')}{mark}")
