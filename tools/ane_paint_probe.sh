#!/bin/bash
# Build the paint probe and prove its logic in QEMU (plus a static proof of the
# device build's channel addresses - the RCH probe's missing-movk bug is
# exactly what that check exists to catch).
#
# QEMU: channel bases point at RAM with NONZERO low halves (so a missing movk
# is a wrong address and would be caught by the static check below); their
# DMA registers read 0, so all four channels are skipped and only the fallback
# paints. The marks record is planted by WITH_SEED, so the bands have known
# input. The check then reads the fallback page and asserts the exact band
# colours, the skipped-channel page stays zero, and the seed record is intact.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_paint.XXXXXX)
mkdir -p artifacts

echo "== assemble"
aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0xE8620000 --defsym RCH_VG1_BASE=0xE8628000 \
  --defsym RCH_G0_BASE=0xE8638000 --defsym RCH_G1_BASE=0xE8640000 \
  --defsym FALLBACK_BASE=0x31000000 --defsym MARKS_BASE=0x348DF000 \
  --defsym PMIC_BASE=0xfff34000 \
  --defsym FILL_LEN=0xC00000 --defsym BAND=0x10000 \
  --defsym WITH_SEED=0 --defsym WITH_SMC=0 \
  -o "$WORK/device.o" ane_paint_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0x44008000 --defsym RCH_VG1_BASE=0x44018000 \
  --defsym RCH_G0_BASE=0x44028000 --defsym RCH_G1_BASE=0x44038000 \
  --defsym FALLBACK_BASE=0x43000000 --defsym MARKS_BASE=0x45000000 \
  --defsym PMIC_BASE=0x46000000 \
  --defsym FILL_LEN=0x100000 --defsym BAND=0x10000 \
  --defsym WITH_SEED=1 --defsym WITH_SMC=0 \
  -o "$WORK/qemu.o" ane_paint_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu payload:   $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== static proof: the channel base values in BOTH builds (device and qemu)"
python3 tools/verify_base_loads.py "$WORK/device.elf" w19 \
  0xE8620000 0xE8628000 0xE8638000 0xE8640000 || exit 1
python3 tools/verify_base_loads.py "$WORK/qemu.elf" w19 \
  0x44008000 0x44018000 0x44028000 0x44038000 || exit 1

echo
echo "== build the Linux arm64 Image (64-byte header) and package (gzip, tiny form)"
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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-paint-probe.img --gzip | head -3

echo
echo "== stock-embedded form (the loader reliably accepts the stock shape; the"
echo "   tiny form is a flaky-payload experiment - use this one on the device)"
python3 mkane_stock_embed.py "$WORK/device.Image" artifacts/fullerene-ane-paint-probe-stock.img

echo
echo "== QEMU check: fallback paints [white, green, blue, yellow], then black"
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
        ready, _, _ = select.select([proc.stdout], [], [], max(0.1, deadline - time.time()))
        if not ready: continue
        line = proc.stdout.readline()
        if not line: return None
        try: msg = json.loads(line)
        except json.JSONDecodeError: continue
        if "return" in msg or "error" in msg: return msg
    return None

def xp(addr, count):
    reply = qmp({"execute": "human-monitor-command",
                 "arguments": {"command-line": f"xp /{count}bx {addr}"}})
    return bytes(int(t, 16) for t in re.findall(r"0x([0-9a-fA-F]{2})\b", (reply or {}).get("return", "")))

qmp({"execute": "qmp_capabilities"})
time.sleep(3)
seed = xp("0x45000000", 8)
b0, b1 = xp("0x43000000", 4), xp("0x43010000", 4)
b2, b3 = xp("0x43020000", 4), xp("0x43030000", 4)
b4, ch = xp("0x43040000", 4), xp("0x44008000", 4)
b14, b15 = xp("0x430E0000", 4), xp("0x430F0000", 4)
qmp({"execute": "quit"})
try: proc.wait(timeout=10)
except subprocess.TimeoutExpired: proc.kill()

want = {"seed": bytes.fromhex("414e454d03000000"),
        "band0 white": bytes.fromhex("ffffffff"),
        "band1 green": bytes.fromhex("00ff00ff"),
        "band2 blue": bytes.fromhex("0000ffff"),
        "band3 yellow": bytes.fromhex("ffff00ff"),
        "band4 black": bytes.fromhex("000000ff"),
        "skipped channel": bytes.fromhex("00000000"),
        "band14 pmic18B green": bytes.fromhex("00ff00ff"),
        "band15 pmic62C green": bytes.fromhex("00ff00ff")}
got = {"seed": seed, "band0 white": b0, "band1 green": b1, "band2 blue": b2,
       "band3 yellow": b3, "band4 black": b4, "skipped channel": ch,
       "band14 pmic18B green": b14, "band15 pmic62C green": b15}
ok = True
for key, expected in want.items():
    good = got[key] == expected
    ok &= good
    print(f"  {key:16s}: {got[key].hex(' ')}  (want {expected.hex(' ')})  {'ok' if good else 'MISMATCH'}")
print()
print("  PASS: seed read, bands painted in order, skipped channel untouched" if ok else "  FAIL")
sys.exit(0 if ok else 1)
PY

echo
echo "== results"
ls -la artifacts/fullerene-ane-paint-probe.img
echo "device readout: count+1 bands = white + one per step mark;"
echo "  band k colour = PAL[k%8] = white green blue yellow cyan magenta red orange"
