#!/bin/bash
cd ~/dev/p20-root
UV=/home/placeless/.hermes/bin/uv
timeout 580 "$UV" run --with pyusb --no-project python3 - <<'PYEOF' 2>&1 | tail -10
import usb.core, usb.util, struct, time
def frame(cmd,a0,a1,p=b""):
    cs=sum(p)&0xFFFFFFFF
    return struct.pack("<IIIIII",cmd,a0,a1,len(p),cs,cmd^0xFFFFFFFF)+p
dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
if dev is None: print('no device'); raise SystemExit(1)
ok=False
for _ in range(20):
    try: usb.util.claim_interface(dev,0); ok=True; break
    except Exception as e: print('claim retry:', e); time.sleep(1)
if not ok: raise SystemExit(1)
pkt = frame(0x4E584E43, 0x01000001, 4096, b"host::adbtest\x00")
dev.write(0x01, pkt, timeout=3000)
print('CNXN staged at', time.strftime('%H:%M:%S'))
buf=b''; t0=time.time()
while time.time()-t0 < 500:
    try:
        x = bytes(dev.read(0x81, 65536, timeout=3000))
        if x:
            buf += x
            print(f'+{time.time()-t0:.0f}s read {len(buf)}')
            if len(buf) > 100: break
    except Exception: pass
print('total:', len(buf))
if buf: open('rings_night/v328_deferred.bin','wb').write(buf)
PYEOF
