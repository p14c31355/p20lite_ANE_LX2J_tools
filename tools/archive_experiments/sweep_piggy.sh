#!/bin/bash
# After the next clean attach, fire a non-magic piggyback every 8 s for
# 3 minutes; keep every file.
set +m
cd ~/dev/p20-root
UV=/home/placeless/.hermes/bin/uv
BASE=$(journalctl -k --no-pager | grep -c 'Product: ANE fastboot')
for i in $(seq 1 150); do
  N=$(journalctl -k --no-pager | grep -c 'Product: ANE fastboot')
  [ "$N" -gt "$BASE" ] && { echo "attach $(date +%H:%M:%S)"; break; }
  sleep 0.5
done
for i in $(seq 0 22); do
  "$UV" run --with pyusb --no-project python3 - <<PYEOF 2>/dev/null
import usb.core, usb.util, struct, time
def frame(cmd,a0,a1,p=b""):
    cs=sum(p)&0xFFFFFFFF
    return struct.pack("<IIIIII",cmd,a0,a1,len(p),cs,cmd^0xFFFFFFFF)+p
dev=usb.core.find(idVendor=0x18D1,idProduct=0xD00D)
if dev is None: raise SystemExit(1)
for _ in range(5):
    try:
        usb.util.claim_interface(dev,0); break
    except Exception: time.sleep(0.3)
pkt=frame(0x4E584E43,0x01000001,4096,b"host::adbtest\x00")
try: dev.write(0x01,pkt,timeout=2000)
except Exception as e: raise SystemExit(1)
buf=b""; t0=time.time()
while time.time()-t0<4:
    try:
        x=bytes(dev.read(0x81,65536,timeout=800))
        if x: buf+=x
    except Exception: pass
open("rings_night/sweep_${i}.bin","wb").write(buf)
print("sweep $i:", len(buf))
PYEOF
  sleep 8
done
