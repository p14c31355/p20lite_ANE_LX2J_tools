#!/bin/bash
# Build the stamp probe (candidate self-identification) and verify it.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_stamp.XXXXXX)
mkdir -p artifacts

echo "== assemble (device + qemu)"
aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0xE8643000 --defsym RCH_VG1_BASE=0xE8642000 \
  --defsym RCH_G0_BASE=0xE8604000  --defsym RCH_G1_BASE=0xE8640000 \
  --defsym RCH_D0_BASE=0xE8644000  --defsym RCH_D1_BASE=0xE8645000 \
  --defsym RCH_D2_BASE=0xE8646000  --defsym RCH_D3_BASE=0xE8647000 \
  --defsym RCH_WCH0_BASE=0xE865A000 --defsym RCH_WCH1_BASE=0xE865B000 \
  --defsym STAMP_RUN=0x40000 --defsym STAMP_LEN=0x200000 \
  --defsym RAMO_WIN_START=0x34800000 --defsym RAMO_WIN_END=0x34900000 \
  --defsym RELOC_DEST=0x31100000 \
  --defsym SPIN_HOLD=0x60000000 --defsym HOLD_REPEATS=18 \
  --defsym WITH_SEED=0 \
  -o "$WORK/device.o" ane_stamp_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0x44008000 --defsym RCH_VG1_BASE=0x44018000 \
  --defsym RCH_G0_BASE=0x44028000  --defsym RCH_G1_BASE=0x44038000 \
  --defsym RCH_D0_BASE=0x44048000  --defsym RCH_D1_BASE=0x44058000 \
  --defsym RCH_D2_BASE=0x44068000  --defsym RCH_D3_BASE=0x44078000 \
  --defsym RCH_WCH0_BASE=0x44088000 --defsym RCH_WCH1_BASE=0x44098000 \
  --defsym STAMP_RUN=0x40000 --defsym STAMP_LEN=0x200000 \
  --defsym RAMO_WIN_START=0x34800000 --defsym RAMO_WIN_END=0x34900000 \
  --defsym RELOC_DEST=0x50000000 \
  --defsym SPIN_HOLD=0x100000 --defsym HOLD_REPEATS=1 \
  --defsym WITH_SEED=1 \
  -o "$WORK/qemu.o" ane_stamp_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu payload:   $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== static proof: base loads, both builds"
python3 tools/verify_base_loads.py "$WORK/device.elf" w19 \
  0xE8643000 0xE8642000 0xE8604000 0xE8640000 0xE8644000 \
  0xE8645000 0xE8646000 0xE8647000 0xE865A000 0xE865B000 || exit 1
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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-stamp-probe.img --gzip | head -3
python3 mkane_stock_embed.py "$WORK/device.Image" artifacts/fullerene-ane-stamp-probe-stock.img

echo
echo "== QEMU check: seed WCH1 slot = 0x44100000 -> its stamp decodes index 9"
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
time.sleep(4)
runs = [xp(0x44100000 + j * 0x40000, 4) for j in range(8)]
past = xp(0x44300000, 4)
slot = xp(0x44098060, 4)     # the seeded WCH1 slot itself
qmp({"execute": "quit"})
try: proc.wait(timeout=10)
except subprocess.TimeoutExpired: proc.kill()
# index 9 = 0b1001: bit0=1, bit1=0, bit2=0, bit3=1; then marker white green blue yellow
want = [(0x44100000 + j * 0x40000, bytes.fromhex(h)) for j, h in enumerate(
    ["ffffffff", "000000ff", "000000ff", "ffffffff", "ffffffff", "00ff00ff", "0000ffff", "ffff00ff"])]
ok = True
for (addr, expected), got in zip(want, runs):
    good = got == expected
    ok &= good
    print(f"  0x{addr:x}: {got.hex(' ')}  (want {expected.hex(' ')})  {'ok' if good else 'MISMATCH'}")
for key, got, expected in (("past stamp", past, bytes(4)),
                           ("seeded slot", slot, bytes.fromhex("00001044"))):
    good = got == expected
    ok &= good
    print(f"  {key:11s}: {got.hex(' ')}  (want {expected.hex(' ')})  {'ok' if good else 'MISMATCH'}")
print()
print("  PASS: WCH1's stamp decodes index 9, nothing painted elsewhere, seed intact"
      if ok else "  FAIL")
sys.exit(0 if ok else 1)
PY

echo
echo "== results"
ls -la artifacts/fullerene-ane-stamp-probe*.img
echo "device readout: for the visible 8-run stamp, runs 0..3 = candidate index"
echo "  in binary (white=1, black=0); runs 4..7 = white green blue yellow."
echo "  index order: 0 VG0, 1 VG1, 2 G0, 3 G1, 4 D0, 5 D1, 6 D2, 7 D3, 8 WCH0, 9 WCH1"
