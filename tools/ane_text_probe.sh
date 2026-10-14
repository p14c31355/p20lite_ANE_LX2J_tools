#!/bin/bash
# Build the text probe (screen console: hex text via 8x8 font) and verify.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_text.XXXXXX)
mkdir -p artifacts

echo "== assemble (device + qemu)"
aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0xE8620000 --defsym RCH_VG1_BASE=0xE8628000 \
  --defsym RCH_G0_BASE=0xE8638000  --defsym RCH_G1_BASE=0xE8640000 \
  --defsym RCH_D0_BASE=0xE8650000  --defsym RCH_D1_BASE=0xE8651000 \
  --defsym RCH_D2_BASE=0xE8652000  --defsym RCH_D3_BASE=0xE8653000 \
  --defsym RCH_WCH0_BASE=0xE865A000 --defsym RCH_WCH1_BASE=0xE865C000 \
  --defsym MARKS_BASE=0x348DF000 \
  --defsym FALLBACK_BASE=0x31000000 \
  --defsym TEXT_BUF=0x1AE2000 --defsym BITMAP=0x1AE3000 \
  --defsym BITMAP_LEN=0x210000 --defsym RENDER_LEN=0x210000 \
  --defsym P_LO=0x1AE0000 --defsym P_HI=0x1B10000 \
  --defsym GATE_HI=0xC0000000 --defsym SKIP_P=1 \
  --defsym RAMO_WIN_START=0x34800000 --defsym RAMO_WIN_END=0x34900000 \
  --defsym SPIN_HOLD=0x60000000 --defsym HOLD_REPEATS=18 \
  --defsym WITH_SEED=0 \
  -o "$WORK/device.o" ane_text_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0x44008000 --defsym RCH_VG1_BASE=0x44018000 \
  --defsym RCH_G0_BASE=0x44028000  --defsym RCH_G1_BASE=0x44038000 \
  --defsym RCH_D0_BASE=0x44048000  --defsym RCH_D1_BASE=0x44058000 \
  --defsym RCH_D2_BASE=0x44068000  --defsym RCH_D3_BASE=0x44078000 \
  --defsym RCH_WCH0_BASE=0x44088000 --defsym RCH_WCH1_BASE=0x44098000 \
  --defsym MARKS_BASE=0x45000000 \
  --defsym FALLBACK_BASE=0x43000000 \
  --defsym TEXT_BUF=0x46000000 --defsym BITMAP=0x46001000 \
  --defsym BITMAP_LEN=0x210000 --defsym RENDER_LEN=0x210000 \
  --defsym P_LO=0x1AE0000 --defsym P_HI=0x1B10000 \
  --defsym GATE_HI=0xC0000000 --defsym SKIP_P=1 \
  --defsym RAMO_WIN_START=0x34800000 --defsym RAMO_WIN_END=0x34900000 \
  --defsym SPIN_HOLD=0x100000 --defsym HOLD_REPEATS=1 \
  --defsym WITH_SEED=1 \
  -o "$WORK/qemu.o" ane_text_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu payload:   $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== static proof: base loads, both builds"
python3 tools/verify_base_loads.py "$WORK/device.elf" w19 \
  0xE8620000 0xE8628000 0xE8638000 0xE8640000 0xE8650000 \
  0xE8651000 0xE8652000 0xE8653000 0xE865A000 0xE865C000 || exit 1
python3 tools/verify_base_loads.py "$WORK/qemu.elf" w19 \
  0x44008000 0x44018000 0x44028000 0x44038000 0x44048000 \
  0x44058000 0x44068000 0x44078000 0x44088000 0x44098000 || exit 1

echo
echo "== build the Linux arm64 Images and package"
python3 - "$WORK" <<'PY'
import struct, sys, pathlib
work = pathlib.Path(sys.argv[1])
for variant in ("device", "qemu"):
    payload = (work / f"{variant}.payload").read_bytes()
    header = bytearray(64)
    struct.pack_into("<II", header, 0, 0x14000010, 0xD503201F)
    struct.pack_into("<Q", header, 8, 0x80000)
    struct.pack_into("<Q", header, 16, 0x400000)
    struct.pack_into("<Q", header, 24, 0x2)
    header[0x38:0x3C] = b"ARM\x64"
    (work / f"{variant}.Image").write_bytes(bytes(header) + payload)
    print(f"  {variant}.Image: {len(header) + len(payload)} bytes")
PY
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-text-fix.img --gzip | head -3
python3 mkane_stock_embed.py "$WORK/device.Image" artifacts/fullerene-ane-text-fix-stock.img

echo
echo "== QEMU check: text string exact, glyph pixels, blit at seeded G1"
python3 - "$WORK/qemu.Image" <<'PY'
import json, re, select, subprocess, sys, time
image = sys.argv[1]
proc = subprocess.Popen(
    ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a53", "-m", "2G",
     "-display", "none", "-serial", "none", "-qmp", "stdio", "-kernel", image],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
def qmp(obj, timeout=15):
    proc.stdin.write((json.dumps(obj) + "\n").encode()); proc.stdin.flush()
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select([proc.stdout], [], [], deadline - time.time())
        if not ready: continue
        line = proc.stdout.readline()
        if not line: return None
        try: msg = json.loads(line)
        except json.JSONDecodeError: continue
        if "return" in msg or "error" in msg: return msg
    return None
def xp(addr, count):
    reply = qmp({"execute": "human-monitor-command",
                 "arguments": {"command-line": f"xp /{count}bx {addr:#x}"}})
    return bytes(int(t, 16) for t in re.findall(r"0x([0-9a-fA-F]{2})\b", (reply or {}).get("return", "")))
qmp({"execute": "qmp_capabilities"})
time.sleep(5)
text = xp(0x46000000, 396)
pix_on = xp(0x46001000 + 0x10E50, 4)    # 'V' gx=1,gy=0 block: cyan
pix_off = xp(0x46001000 + 0x10E40, 4)   # gx=0,gy=0: black
blit_on = xp(0x44100000 + 0x10E50, 4)
blit_off = xp(0x44100000 + 0x10E40, 4)
blit2_on = xp(0x44200000 + 0x10E50, 4)
blit3_on = xp(0x44300000 + 0x10E50, 4)
fallback_on = xp(0x43000000 + 0x10E50, 4)
seed = xp(0x45000000, 8)
qmp({"execute": "quit"})
try: proc.wait(timeout=10)
except subprocess.TimeoutExpired: proc.kill()
v3 = [0x44100000, 0x44200000, 0x44300000]
s = ""
for i in range(10):
    s += f"V{i} "
    for k in range(3):
        val = v3[k] if i == 3 else 0
        s += f"{val:08X}"
    s += " " * 6
rec = bytes.fromhex("414e454d03000000") + b"123\x00" + bytes(13)
s += "RC " + rec[0:12].hex().upper() + " " * 6 + rec[12:24].hex().upper() + " " * 9
expected = s.encode()
want = {"text string": (text, expected),
        "bitmap on-pixel": (pix_on, bytes.fromhex("00ffffff")),
        "bitmap off-pixel": (pix_off, bytes.fromhex("000000ff")),
        "blit slot0 on-pixel": (blit_on, bytes.fromhex("00ffffff")),
        "blit slot0 off-pixel": (blit_off, bytes.fromhex("000000ff")),
        "blit slot1 on-pixel": (blit2_on, bytes.fromhex("00ffffff")),
        "blit slot2 on-pixel": (blit3_on, bytes.fromhex("00ffffff")),
        "fallback on-pixel": (fallback_on, bytes.fromhex("00ffffff")),
        "seed ANEM,3": (seed, bytes.fromhex("414e454d03000000"))}
ok = True
for key, (got, exp) in want.items():
    good = got == exp
    ok &= good
    if key == "text string":
        print(f"  {key}: {'ok' if good else 'MISMATCH'}")
        if not good:
            print(f"    got: {got[:80]!r}")
            print(f"    exp: {exp[:80]!r}")
    else:
        print(f"  {key:16s}: {got.hex(' ')}  (want {exp.hex(' ')})  {'ok' if good else 'MISMATCH'}")
print()
print("  PASS: text built, glyphs rendered, blit landed at the seeded target"
      if ok else "  FAIL")
sys.exit(0 if ok else 1)
PY

echo
echo "== results"
ls -la artifacts/fullerene-ane-text-probe*.img
