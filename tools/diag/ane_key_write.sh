#!/bin/bash
# Build the key writer.  Defaults: KEYREG=0x18B, KEYVAL=0x01 - the reason-probe
# v2's already-tested write, so the default build is a rehearsal of known
# behaviour.  The real build comes after the key probe names the register:
#   --defsym KEYREG=<offset> --defsym KEYVAL=<held value>
# (edit KEYREG/KEYVAL below, or pass them as $1/$2).
#
# QEMU proof: the window points at RAM; the sequence must read 0 before,
# then read back the written value twice.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_keyw.XXXXXX)
mkdir -p artifacts

KEYREG=${1:-0x18B}
KEYVAL=${2:-0x01}
echo "== target: PMIC +$KEYREG <- $KEYVAL"

echo "== assemble"
aarch64-linux-gnu-as \
  --defsym PMIC_BASE=0xfff34000 \
  --defsym TRACE_BASE=0x348c0000 --defsym WITH_TRACE=1 \
  --defsym KEYREG=$KEYREG --defsym KEYVAL=$KEYVAL \
  -o "$WORK/device.o" ane_key_write.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym PMIC_BASE=0x42006000 \
  --defsym TRACE_BASE=0x42001000 --defsym WITH_TRACE=1 \
  --defsym KEYREG=$KEYREG --defsym KEYVAL=$KEYVAL \
  -o "$WORK/qemu.o" ane_key_write.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu   payload: $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== disassembly: the store to the target register"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | grep -E "str\s+w14" | head -3

echo
echo "== build the Linux arm64 Images"
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

echo
echo "== package the device image (gzip)"
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-key-write.img --gzip | head -3

echo
echo "== QEMU check: read 0, write, readback twice"
python3 - "$WORK/qemu.Image" "$KEYVAL" <<'PY'
import json, re, select, struct, subprocess, sys, time

keyval = int(sys.argv[2], 16)
expected = struct.pack("<6I", 1, 0, 2, keyval, 3, keyval)

proc = subprocess.Popen(
    ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a53", "-m", "2G",
     "-display", "none", "-serial", "none", "-qmp", "stdio",
     "-kernel", sys.argv[1]],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

def qmp(obj, timeout=10):
    proc.stdin.write((json.dumps(obj) + "\n").encode())
    proc.stdin.flush()
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select([proc.stdout], [], [], deadline - time.time())
        if not ready:
            continue
        line = proc.stdout.readline()
        if not line:
            return None
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "return" in msg or "error" in msg:
            return msg
    return None

def dump(addr, count):
    reply = qmp({"execute": "human-monitor-command",
                 "arguments": {"command-line": f"xp /{count}bx {addr}"}})
    text = (reply or {}).get("return", "")
    return bytes(int(t, 16) for t in re.findall(r"0x([0-9a-fA-F]{2})\b", text))

qmp({"execute": "qmp_capabilities"})
t0 = time.time()
got = b""
while time.time() - t0 < 60:
    time.sleep(2)
    got = dump(0x42001000, 24)
    if got[:24] == expected[:24]:
        break
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

ok = got[:24] == expected[:24]
print(f"  trace got     : {got[:24].hex(' ')}")
print(f"  trace want    : {expected[:24].hex(' ')}")
print()
if ok:
    print("  PASS: pre-read, write, readback all exact")
else:
    print("  FAIL: mismatch above")
sys.exit(0 if ok else 1)
PY
echo "KEYWRITE_BUILD_EXIT=$?"
