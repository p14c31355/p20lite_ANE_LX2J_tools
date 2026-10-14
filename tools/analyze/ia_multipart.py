#!/usr/bin/env python3
"""S3 multipart upload to Internet Archive (100 MiB parts) - auth v2."""
import os, sys, hashlib, time, re, base64, email.utils, hmac
import urllib.request, urllib.error

IDENT = "p20lite-ane-lx2j-stock-firmware"
LOCAL = "/home/placeless/dev/p20-root/firmware/ANE-LX2J_8.0.0.110_C635.rar"
REMOTE = "ANE-LX2J_8.0.0.110(C635)_Firmware_Android_8.0.0_EMUI_8.0.0.rar"
PART = 100 * 1024 * 1024  # 100 MiB

acc = sec = None
for line in open(os.path.expanduser("~/.config/ia.ini")):
    if line.startswith("access"): acc = line.split("=", 1)[1].strip()
    elif line.startswith("secret"): sec = line.split("=", 1)[1].strip()

def headers_for(method, resource, extra=None):
    date = email.utils.formatdate(usegmt=True)
    to_sign = f"{method}\n\n\n{date}\n{extra_line}\n{resource}" if (extra_line := "") else f"{method}\n\n\n{date}\n{resource}"
    sig = base64.b64encode(hmac.new(sec.encode(), to_sign.encode(), hashlib.sha1).digest()).decode()
    h = {"Date": date, "Authorization": f"AWS {acc}:{sig}"}
    if extra: h.update(extra)
    return h

size = os.path.getsize(LOCAL)
n_parts = (size + PART - 1) // PART
md5 = hashlib.md5()
print(f"file: {LOCAL} ({size:,} bytes) -> {n_parts} parts x 100MiB", flush=True)

# 1) initiate (resource includes ?uploads)
date = email.utils.formatdate(usegmt=True)
resource = f"/{IDENT}/{REMOTE}?uploads"
to_sign = f"POST\n\n\n{date}\nx-amz-auto-make-bucket:1\n{resource}"
sig = base64.b64encode(hmac.new(sec.encode(), to_sign.encode(), hashlib.sha1).digest()).decode()
req = urllib.request.Request(
    f"https://s3.us.archive.org{resource}", method="POST",
    headers={"Date": date, "Authorization": f"AWS {acc}:{sig}", "x-amz-auto-make-bucket": "1"}, data=b"")
body = urllib.request.urlopen(req, timeout=120).read().decode()
upload_id = re.search(r"<UploadId>([^<]+)</UploadId>", body).group(1)
print(f"uploadId: {upload_id}", flush=True)

# 2) upload parts (signed PUT with ?partNumber=&uploadId= in resource)
etags = []
with open(LOCAL, "rb") as fh:
    for i in range(1, n_parts + 1):
        chunk = fh.read(PART)
        md5.update(chunk)
        part_md5 = base64.b64encode(hashlib.md5(chunk).digest()).decode()
        resource = f"/{IDENT}/{REMOTE}?partNumber={i}&uploadId={upload_id}"
        for attempt in range(1, 6):
            try:
                date = email.utils.formatdate(usegmt=True)
                to_sign = f"PUT\n{part_md5}\n\n{date}\n{resource}"
                sig = base64.b64encode(hmac.new(sec.encode(), to_sign.encode(), hashlib.sha1).digest()).decode()
                req = urllib.request.Request(
                    f"https://s3.us.archive.org{resource}", method="PUT",
                    headers={"Date": date, "Authorization": f"AWS {acc}:{sig}", "Content-MD5": part_md5},
                    data=chunk)
                r = urllib.request.urlopen(req, timeout=900)
                et = r.headers.get("ETag", "").strip('"')
                etags.append((i, et))
                print(f"  part {i}/{n_parts} OK t={time.strftime('%H:%M:%S')}", flush=True)
                break
            except Exception as e:
                print(f"  part {i} attempt {attempt} failed: {e}", flush=True)
                time.sleep(20 * attempt)
        else:
            print("ABORT: part failed after 5 attempts", flush=True)
            sys.exit(1)

# 3) complete
parts_xml = "".join(f"<Part><PartNumber>{i}</PartNumber><ETag>{et}</ETag></Part>" for i, et in etags)
date = email.utils.formatdate(usegmt=True)
resource = f"/{IDENT}/{REMOTE}?uploadId={upload_id}"
to_sign = f"POST\n\n\n{date}\n{resource}"
sig = base64.b64encode(hmac.new(sec.encode(), to_sign.encode(), hashlib.sha1).digest()).decode()
req = urllib.request.Request(
    f"https://s3.us.archive.org{resource}", method="POST",
    headers={"Date": date, "Authorization": f"AWS {acc}:{sig}"},
    data=f"<CompleteMultipartUpload>{parts_xml}</CompleteMultipartUpload>".encode())
resp = urllib.request.urlopen(req, timeout=300).read().decode()
print("complete:", resp[:250], flush=True)
print(f"local md5: {md5.hexdigest()}", flush=True)
print("DONE", flush=True)
