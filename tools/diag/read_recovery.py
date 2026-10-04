#!/usr/bin/env python3
"""
Read the two artefacts that will settle what the pre-checks demand:

 1. sbin/recovery - grep for the check-tree names. This is the 2018-era EMUI 8
    recovery, not the 2022 HarmonyOS one, so whatever it actually looks for is
    authoritative for our package.
 2. dload/update_huawei_dload.zip, embedded in the recovery ramdisk itself - its
    entry list shows the exact file set an update package in this era carries.
"""
import re
import struct
import zipfile

REC = "/tmp/recov/recovery.bin"
EMB = "/tmp/recov/update_huawei_dload.zip"
import os
OUT = "/tmp/recov"

# --- extract the embedded zip out of the cpio we already parsed
raw = open("/tmp/recov/recovery_ramdisk.cpio", "rb").read()
p = 0
emb = None
while p + 110 <= len(raw):
    hdr = raw[p:p + 110]
    if hdr[:6] not in (b"070701", b"070702"):
        nxt = raw.find(b"070701", p)
        if nxt == -1:
            break
        p = nxt
        continue
    f = lambda i: int(hdr[6 + 8 * i: 6 + 8 * (i + 1)], 16)
    filesize, namesize = f(6), f(11)
    name = raw[p + 110:p + 110 + namesize - 1].decode("utf-8", "replace")
    body = p + 110 + namesize
    body += (-body) % 4
    if name.endswith("update_huawei_dload.zip"):
        emb = raw[body:body + filesize]
        break
    body += filesize
    body += (-body) % 4
    p = body

if emb:
    open(EMB, "wb").write(emb)
    print(f"=== embedded package: {len(emb):,} bytes ===")
    with zipfile.ZipFile(EMB) as z:
        for i in z.infolist():
            print(f"   {i.file_size:>10} {i.compress_size:>10}  {i.filename}")
        print("\n   comment:", z.comment[:80] if z.comment else b"(none)")
        for nm in ("SOFTWARE_VER_LIST.mbn", "SD_update.tag", "full_mainpkg.tag",
                   "BOARDID_LIST.mbn", "VERSION.mbn", "UPT_VER.tag"):
            try:
                d = z.read(nm)
                print(f"   {nm} = {d!r}")
            except KeyError:
                pass
else:
    print("embedded package not found")

# --- grep the recovery binary
print("\n=== sbin/recovery: which entries does it look for? ===")
blob = open(REC, "rb").read()
strs = re.findall(rb"[ -~]{4,120}", blob)
joined = b"\n".join(strs)
names = ["SOFTWARE_VER_LIST.mbn", "SD_update.tag", "OTA_update.tag", "full_mainpkg.tag",
         "full_datapkg.tag", "BOARDID_LIST.mbn", "packageinfo.mbn", "VERSION.mbn",
         "skipauth_pkg.tag", "sec_xloader_header", "UPT_VER.tag",
         "hotakey_sign_version.tag", "version.prop", "dload/", "update_huawei_dload.zip",
         "CheckVersionInZipPkg", "DoCheckVersion", "CheckBoardIdInfo", "CheckPackageInfo"]
for n in names:
    c = joined.count(n.encode())
    print(f"   {n:32} {c}")

print("\n=== literal .tag / .mbn / .zip strings inside the recovery ===")
for s in sorted(set(re.findall(rb"[A-Za-z0-9_./-]+\.(?:tag|mbn|zip|prop)", joined))):
    print("   ", s.decode())
