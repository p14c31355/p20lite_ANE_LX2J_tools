#!/bin/bash
# Extract UPDATE.APP to disk once and parse it as a plain file. The streaming
# version kept losing blocks at chunk boundaries; a 4.3 GB file is easier and we
# have the disk space.
set -u
cd /home/placeless/dev/p20-root
mkdir -p /tmp/app
APP=/tmp/app/UPDATE.APP

if [ ! -f "$APP" ]; then
  echo "### extracting UPDATE.APP from the original update_sd.zip"
  python3 - <<'PY'
import zipfile, shutil, time
t=time.time()
with zipfile.ZipFile('/tmp/orig/update_sd.zip') as z, z.open('UPDATE.APP') as f, open('/tmp/app/UPDATE.APP','wb') as out:
    n=0
    while True:
        b=f.read(1<<22)
        if not b: break
        out.write(b)
        n+=len(b)
        if n % (256<<20) < (1<<22):
            print(f"  {n/2**30:.2f} GiB  ({time.time()-t:.0f}s)")
print("done")
PY
fi
ls -la /tmp/app/ 

echo
echo "### parse the block table"
python3 - <<'PY'
import struct
MAGIC=b"\x55\xaa\x5a\xa5"
data=open('/tmp/app/UPDATE.APP','rb').read()
print(f"file size: {len(data):,}")
pos=0; n=0
while pos < len(data)-100:
    j=data.find(MAGIC,pos)
    if j==-1: break
    hdr_sz,unk1,hw_id,seq,size=struct.unpack("<IIQII",data[j+4:j+28])
    ptype=data[j+60:j+76].decode('ascii','replace').strip('\x00')
    if not (50<=hdr_sz<=4096) or size>5_000_000_000:
        pos=j+1; continue
    print(f"[{n:>2}] @{j:#012x} {ptype:<16} hdr={hdr_sz:<4} payload={size:>12,}")
    n+=1
    pos=j+hdr_sz+size
print(f"\nblocks: {n}")
PY
