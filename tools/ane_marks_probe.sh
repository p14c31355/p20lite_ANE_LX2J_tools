#!/bin/bash
# Build the marks probe (step-mark record as visible bands) and verify it.
#
# The band painter is the QEMU-proven logic from ane_paint_probe.S; the
# candidate set is the rch-probe2 set (the ten channels' DATA_ADDR0 plus the
# fallback) that produced the first visible paint on the device. The QEMU
# variant points the channels at zeroed RAM (reads 0 -> all skipped) and the
# scratch at RAM with WITH_SEED planting "ANEM", 3, "123", so the fallback
# bands run on known input and the expected colours are exact.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_marks.XXXXXX)
mkdir -p artifacts

echo "== assemble"
aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0xE8620000 --defsym RCH_VG1_BASE=0xE8628000 \
  --defsym RCH_G0_BASE=0xE8638000 --defsym RCH_G1_BASE=0xE8640000 \
  --defsym RCH_D0_BASE=0xE8650000 --defsym RCH_D1_BASE=0xE8651000 \
  --defsym RCH_D2_BASE=0xE8652000 --defsym RCH_D3_BASE=0xE8653000 \
  --defsym RCH_WCH0_BASE=0xE865A000 --defsym RCH_WCH1_BASE=0xE865C000 \
  --defsym FALLBACK_BASE=0x31000000 --defsym MARKS_BASE=0x348DF000 \
  --defsym FILL_LEN=0x800000 --defsym BAND=0x80000 \
  --defsym RAMO_WIN_START=0x34800000 --defsym RAMO_WIN_END=0x34900000 \
  --defsym SPIN_HOLD=0x60000000 --defsym HOLD_REPEATS=18 \
  --defsym WITH_SMC=0 --defsym WITH_SEED=0 \
  -o "$WORK/device.o" ane_marks_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0x44008000 --defsym RCH_VG1_BASE=0x44018000 \
  --defsym RCH_G0_BASE=0x44028000 --defsym RCH_G1_BASE=0x44038000 \
  --defsym RCH_D0_BASE=0x44048000 --defsym RCH_D1_BASE=0x44058000 \
  --defsym RCH_D2_BASE=0x44068000 --defsym RCH_D3_BASE=0x44078000 \
  --defsym RCH_WCH0_BASE=0x44088000 --defsym RCH_WCH1_BASE=0x44098000 \
  --defsym FALLBACK_BASE=0x43000000 --defsym MARKS_BASE=0x45000000 \
  --defsym FILL_LEN=0x200000 --defsym BAND=0x80000 \
  --defsym RAMO_WIN_START=0x34800000 --defsym RAMO_WIN_END=0x34900000 \
  --defsym SPIN_HOLD=0x100000 --defsym HOLD_REPEATS=1 \
  --defsym WITH_SMC=0 --defsym WITH_SEED=1 \
  -o "$WORK/qemu.o" ane_marks_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu payload:   $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== disassembly (preamble + seed + marks read)"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | sed -n '/<_start>:/,+6p'

echo
echo "== static proof: the ten channel base addresses, from both builds"
python3 tools/verify_base_loads.py "$WORK/device.elf" w19 \
  0xE8620000 0xE8628000 0xE8638000 0xE8640000 \
  0xE8650000 0xE8651000 0xE8652000 0xE8653000 \
  0xE865A000 0xE865C000 || exit 1
python3 tools/verify_base_loads.py "$WORK/qemu.elf" w19 \
  0x44008000 0x44018000 0x44028000 0x44038000 \
  0x44048000 0x44058000 0x44068000 0x44078000 \
  0x44088000 0x44098000 || exit 1

echo
echo "== build the Linux arm64 Image and package (tiny + stock-embedded)"
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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-marks-probe.img --gzip | head -3
python3 mkane_stock_embed.py "$WORK/device.Image" artifacts/fullerene-ane-marks-probe-stock.img

echo
echo "== QEMU check: seed 'ANEM',3,'123' -> 4 bands on the fallback, channels skipped"
python3 - "$WORK/qemu.Image" <<'PY'
import json, re, select, subprocess, sys, time
image = sys.argv[1]
CHANNELS = [0x44008000, 0x44018000, 0x44028000, 0x44038000,
            0x44048000, 0x44058000, 0x44068000, 0x44078000,
            0x44088000, 0x44098000]
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
seed = xp(0x45000000, 8)
b0 = xp(0x43000000, 4)      # band 0 white
b1 = xp(0x43080000, 4)      # band 1 green
b2 = xp(0x43100000, 4)      # band 2 blue
b3 = xp(0x43180000, 4)      # band 3 yellow
past = xp(0x43200000, 4)    # beyond FILL_LEN: untouched
chan = [xp(c, 4) for c in CHANNELS]
qmp({"execute": "quit"})
try: proc.wait(timeout=10)
except subprocess.TimeoutExpired: proc.kill()
want = {"seed ANEM,3": (seed, bytes.fromhex("414e454d03000000")),
        "band 0 white": (b0, bytes.fromhex("ffffffff")),
        "band 1 green": (b1, bytes.fromhex("00ff00ff")),
        "band 2 blue":  (b2, bytes.fromhex("0000ffff")),
        "band 3 yellow": (b3, bytes.fromhex("ffff00ff")),
        "past fill zero": (past, bytes(4))}
ok = True
for key, (got, expected) in want.items():
    good = got == expected
    ok &= good
    print(f"  {key:16s}: {got.hex(' ')}  (want {expected.hex(' ')})  {'ok' if good else 'MISMATCH'}")
for c, word in zip(CHANNELS, chan):
    good = word == bytes(4)
    ok &= good
    print(f"  channel {c:#x}: {word.hex(' ')} (want zeros)")
print()
print("  PASS: bands painted in order on the fallback, channels skipped, seed intact"
      if ok else "  FAIL")
sys.exit(0 if ok else 1)
PY

echo
echo "== results"
ls -la artifacts/fullerene-ane-marks-probe*.img
echo "device readout: band 0 white + one band per step mark;"
echo "  band k colour = PAL[k%8] = white green blue yellow cyan magenta red orange"
echo "  expect the kill build's record 123456F -> 8 bands"
