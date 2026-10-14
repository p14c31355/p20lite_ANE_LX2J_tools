#!/usr/bin/env python3
"""Complete the multipart upload (retry after 400: list parts first, use server ETags)."""
import os, re, base64, email.utils, hmac, hashlib
import urllib.request, urllib.error

IDENT = "p20lite-ane-lx2j-stock-firmware"
REMOTE = "ANE-LX2J_8.0.0.110(C635)_Firmware_Android_8.0.0_EMUI_8.0.0.rar"

acc = sec = None
for line in open(os.path.expanduser("~/.config/ia.ini")):
    if line.startswith("access"): acc = line.split("=", 1)[1].strip()
    elif line.startswith("secret"): sec = line.split("=", 1)[1].strip()

def signed(method, resource, data=None, headers=None, md5b64=""):
    date = email.utils.formatdate(usegmt=True)
    to_sign = f"{method}\n{md5b64}\n\n{date}\n{resource}"
    sig = base64.b64encode(hmac.new(sec.encode(), to_sign.encode(), hashlib.sha1).digest()).decode()
    h = {"Date": date, "Authorization": f"AWS {acc}:{sig}"}
    if headers: h.update(headers)
    return urllib.request.Request(f"https://s3.us.archive.org{resource}", method=method, headers=h, data=data)

# find the uploadId: list multipart uploads
r = urllib.request.urlopen(signed("GET", f"/{IDENT}?uploads"), timeout=60).read().decode()
m = re.search(r"<UploadId>([^<]+)</UploadId>.*?<Key>([^<]+)</Key>", r, re.S)
ids = re.findall(r"<UploadId>([^<]+)</UploadId>", r)
keys = re.findall(r"<Key>([^<]+)</Key>", r)
print("uploads in flight:", list(zip(keys, ids)))
uid = None
for k, i in zip(keys, ids):
    if "110" in k and k.endswith(".rar"): uid = i
if not uid:
    print("no in-flight upload found"); raise SystemExit(1)
print("uploadId:", uid)

# list uploaded parts (authoritative ETags)
r = urllib.request.urlopen(signed("GET", f"/{IDENT}/{REMOTE}?uploadId={uid}"), timeout=60).read().decode()
parts = re.findall(r"<Part><PartNumber>(\d+)</PartNumber>.*?<ETag>&quot;([^&]+)&quot;</ETag>", r, re.S)
if not parts:
    parts = re.findall(r"<PartNumber>(\d+)</PartNumber>.*?<ETag>([^<]+)</ETag>", r, re.S)
print(f"server has {len(parts)} parts")
parts_xml = "".join(
    f"<Part><PartNumber>{n}</PartNumber><ETag>{e if e.startswith(chr(34)) else chr(34)+e+chr(34)}</ETag></Part>"
    for n, e in parts)

resource = f"/{IDENT}/{REMOTE}?uploadId={uid}"
req = signed("POST", resource, data=f"<CompleteMultipartUpload>{parts_xml}</CompleteMultipartUpload>".encode())
try:
    resp = urllib.request.urlopen(req, timeout=300).read().decode()
    print("complete OK:", resp[:300])
except urllib.error.HTTPError as e:
    print("HTTP", e.code, e.read().decode()[:500])
