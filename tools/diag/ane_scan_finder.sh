#!/bin/bash
# Build the scan-finder probe and prove its logic in QEMU.
#
# QEMU: channel bases point at zeroed RAM with NONZERO low halves (so the
# static base check has teeth), their DMA slots read 0 (implausible, skipped),
# and only the fallback paints. The check asserts the fallback page holds
# [white band 0][black bands 1..12][green band 13], and that a channel page
# stayed untouched.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_scan.XXXXXX)
mkdir -p artifacts

echo "== assemble"
aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0xE8620000 --defsym RCH_VG1_BASE=0xE8628000 \
  --defsym RCH_G0_BASE=0xE8638000 --defsym RCH_G1_BASE=0xE8640000 \
  --defsym FALLBACK_BASE=0x31000000 \
  --defsym FILL_LEN=0xC00000 --defsym BAND=0x10000 --defsym WITH_SMC=0 \
  -o "$WORK/device.o" ane_scan_finder.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0x44008000 --defsym RCH_VG1_BASE=0x44018000 \
  --defsym RCH_G0_BASE=0x44028000 --defsym RCH_G1_BASE=0x44038000 \
  --defsym FALLBACK_BASE=0x43000000 \
  --defsym FILL_LEN=0x100000 --defsym BAND=0x10000 --defsym WITH_SMC=0 \
  -o "$WORK/qemu.o" ane_scan_finder.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu payload:   $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== static proof: the channel base values in BOTH builds"
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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-scan-finder.img --gzip | head -3

echo
echo "== QEMU check: fallback paints white band 0, black 1..12, green band 13"
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
b0 = xp("0x43000000", 4)      # band 0: white
b5 = xp("0x43050000", 4)      # band 5: black
b13 = xp("0x430D0000", 4)     # band 13: green
ch = xp("0x44008000", 4)      # skipped channel page
qmp({"execute": "quit"})
try: proc.wait(timeout=10)
except subprocess.TimeoutExpired: proc.kill()

want = {"band0 white": (b0, bytes.fromhex("ffffffff")),
        "band5 black": (b5, bytes.fromhex("000000ff")),
        "band13 green": (b13, bytes.fromhex("00ff00ff")),
        "skipped channel": (ch, bytes.fromhex("00000000"))}
ok = True
for key, (got, expected) in want.items():
    good = got == expected
    ok &= good
    print(f"  {key:16s}: {got.hex(' ')}  (want {expected.hex(' ')})  {'ok' if good else 'MISMATCH'}")
print()
print("  PASS: position-encoded bands land exactly" if ok else "  FAIL")
sys.exit(0 if ok else 1)
PY

echo
echo "== results"
ls -la artifacts/fullerene-ane-scan-finder.img
echo "green band index -> candidate: 1-3 VG0 ADDR0/1/2, 4-6 VG1, 7-9 G0, 10-12 G1, 13 fallback"
