#!/bin/bash
# Build the text carpet probe (text stamped across the whole range) and verify.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_carpet.XXXXXX)
mkdir -p artifacts

echo "== assemble (device + qemu)"
aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0xE8643000 --defsym RCH_VG1_BASE=0xE8642000 \
  --defsym RCH_G0_BASE=0xE8604000  --defsym RCH_G1_BASE=0xE8640000 \
  --defsym RCH_D0_BASE=0xE8644000  --defsym RCH_D1_BASE=0xE8645000 \
  --defsym RCH_D2_BASE=0xE8646000  --defsym RCH_D3_BASE=0xE8647000 \
  --defsym RCH_WCH0_BASE=0xE865A000 --defsym RCH_WCH1_BASE=0xE865B000 \
  --defsym MARKS_BASE=0x348DF000 \
  --defsym TEXT_BUF=0x1AE2000 --defsym BITMAP=0x1AE3000 \
  --defsym BITMAP_LEN=0x210000 \
  --defsym ISLAND_LO=0x1AE0000 --defsym ISLAND_HI=0x1AF8000 \
  --defsym CARPET_LO=0x1840000 --defsym CARPET_HI=0x1C60000 \
  --defsym STAMP_STEP=0x40000 \
  --defsym SPIN_HOLD=0x60000000 --defsym HOLD_REPEATS=18 \
  -o "$WORK/device.o" ane_text_carpet.S
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
  --defsym TEXT_BUF=0x46000000 --defsym BITMAP=0x46001000 \
  --defsym BITMAP_LEN=0x210000 \
  --defsym ISLAND_LO=0x41400000 --defsym ISLAND_HI=0x41480000 \
  --defsym CARPET_LO=0x41000000 --defsym CARPET_HI=0x41800000 \
  --defsym STAMP_STEP=0x40000 \
  --defsym SPIN_HOLD=0x100000 --defsym HOLD_REPEATS=1 \
  -o "$WORK/qemu.o" ane_text_carpet.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu payload:   $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== static proof: base loads (branch-coupled chain shape), both builds"
python3 tools/verify_base_pairs.py "$WORK/device.elf" w19 \
  0xE8643000 0xE8642000 0xE8604000 0xE8640000 0xE8644000 \
  0xE8645000 0xE8646000 0xE8647000 0xE865A000 0xE865B000 || exit 1
python3 tools/verify_base_pairs.py "$WORK/qemu.elf" w19 \
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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-text-carpet.img --gzip | head -3
python3 mkane_stock_embed.py "$WORK/device.Image" artifacts/fullerene-ane-text-carpet-stock.img

echo
echo "== QEMU check: carpet stamps at CARPET_LO and CARPET_LO+step"
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
time.sleep(6)
text = xp(0x46000000, 396)
stamp0_on = xp(0x41000000 + 0x10E50, 4)
stamp0_off = xp(0x41000000 + 0x10E40, 4)
clip_on = xp(0x413C0000 + 0x10E50, 4)      # clipped stamp: top of bitmap lands
island_zero = xp(0x41400000 + 0x10E50, 4)  # island region stays untouched
resume_on = xp(0x41480000 + 0x10E50, 4)    # stamps above the island run full
beyond = xp(0x41A00000, 4)
qmp({"execute": "quit"})
try: proc.wait(timeout=10)
except subprocess.TimeoutExpired: proc.kill()
s = ""
for i in range(10):
    s += f"V{i} " + "00000000" * 3 + " " * 6
s += "RC " + "00" * 12 + " " * 6 + "00" * 12 + " " * 9
want = {"text string": (text, s.encode()),
        "stamp0 on-pixel": (stamp0_on, bytes.fromhex("00ffffff")),
        "stamp0 off-pixel": (stamp0_off, bytes.fromhex("000000ff")),
        "clip-boundary on-pixel": (clip_on, bytes.fromhex("00ffffff")),
        "island untouched": (island_zero, bytes(4)),
        "resume above island": (resume_on, bytes.fromhex("00ffffff")),
        "beyond zero": (beyond, bytes(4))}
ok = True
for key, (got, exp) in want.items():
    good = got == exp
    ok &= good
    if key == "text string":
        print(f"  {key}: {'ok' if good else 'MISMATCH'}")
    else:
        print(f"  {key:16s}: {got.hex(' ')}  (want {exp.hex(' ')})  {'ok' if good else 'MISMATCH'}")
print()
print("  PASS: text built (zeros), carpet stamped at both spots, range respected"
      if ok else "  FAIL")
sys.exit(0 if ok else 1)
PY

echo
echo "== results"
ls -la artifacts/fullerene-ane-text-carpet*.img
