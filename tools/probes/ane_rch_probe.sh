#!/bin/bash
# Build the RCH probe and verify its logic in QEMU.
#
# The QEMU variant points the four RCH bases at zeroed RAM: the reads return 0,
# which is below the plausibility floor, so every channel is skipped and only
# the fallback fill runs. That is the macro + range-check path under test; the
# register addresses themselves come from the vendor tree.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_rch.XXXXXX)
mkdir -p artifacts

echo "== assemble"
aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0xE8620000 --defsym RCH_VG1_BASE=0xE8628000 \
  --defsym RCH_G0_BASE=0xE8638000 --defsym RCH_G1_BASE=0xE8640000 \
  --defsym FALLBACK_BASE=0x31000000 --defsym FILL_LEN=0xC00000 \
  --defsym SPIN_HOLD=0x60000000 --defsym HOLD_REPEATS=18 --defsym WITH_SMC=0 \
  -o "$WORK/device.o" ane_rch_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0x44000000 --defsym RCH_VG1_BASE=0x44010000 \
  --defsym RCH_G0_BASE=0x44020000 --defsym RCH_G1_BASE=0x44030000 \
  --defsym FALLBACK_BASE=0x43000000 --defsym FILL_LEN=0x100000 \
  --defsym SPIN_HOLD=0x100000 --defsym HOLD_REPEATS=1 --defsym WITH_SMC=0 \
  -o "$WORK/qemu.o" ane_rch_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu payload: $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== disassembly (preamble + one channel + fallback)"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | sed -n '/<_start>:/,+8p'

echo
echo "== static proof: the four channel base addresses, from the device build"
python3 tools/verify_base_loads.py "$WORK/device.elf" w19 \
  0xE8620000 0xE8628000 0xE8638000 0xE8640000 || exit 1

echo
echo "== Image + package (stock-embedded form)"
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
python3 mkane_stock_embed.py "$WORK/device.Image" artifacts/fullerene-ane-rch-probe-hang.img

echo
echo "== QEMU check: all channels implausible (reads 0) -> only the fallback fills"
python3 - "$WORK/qemu.Image" <<'PY'
import json, re, select, struct, subprocess, sys, time
image = sys.argv[1]
color = struct.pack("<I", 0xFF00FF00)     # the fallback's word (as stored)
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
                 "arguments": {"command-line": f"xp /{count}bx {addr}"}})
    return bytes(int(t, 16) for t in re.findall(r"0x([0-9a-fA-F]{2})\b", (reply or {}).get("return", "")))
qmp({"execute": "qmp_capabilities"})
time.sleep(4)
first, last = xp("0x43000000", 4), xp("0x430ffffc", 4)
past = xp("0x43100000", 4)
# the qemu channels' regions must still be zero (skipped)
ch0 = xp("0x44000000", 4)
qmp({"execute": "quit"})
try: proc.wait(timeout=10)
except subprocess.TimeoutExpired: proc.kill()
# the fallback colour word is 0xFFFF00FF (magenta in ABGR) -> LE bytes ff 00 ff ff
expect = bytes.fromhex("ff00ffff")
print(f"  fallback first: {first.hex(' ')}  last: {last.hex(' ')}  past: {past.hex(' ')}")
print(f"  skipped channel VG0 @0x44000000: {ch0.hex(' ')} (want zeros)")
ok = first == expect and last == expect and past == b"\x00\x00\x00\x00" and ch0 == b"\x00\x00\x00\x00"
print("  PASS: range check skips implausible, fallback fills exactly" if ok else "  FAIL")
sys.exit(0 if ok else 1)
PY

echo
echo "== results"
ls -la artifacts/fullerene-ane-rch-probe-hang.img
echo "device readout: which colour appears names the scanned channel:"
echo "  green=VG0, blue=VG1, red=G0, cyan=G1, magenta=fallback(0x31000000)"
echo "  (SMC=0: this build HANGS, so the colour stays visible until the loader's"
echo "   watchdog fallback ~4.5 min later; the loader then lands in fastboot)"
