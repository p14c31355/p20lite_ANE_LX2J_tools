#!/bin/bash
# Build the reason probe v2 (traced) and prove it in QEMU first.
#
# Differences from v1: the DEVICE build now carries the trace too (v1 wrote
# blind, which is why its negative result could not be explained), and the
# probe reads the whole HRST window BEFORE writing, so one device run yields
# the pre-write values, the write, and the readback.
#
# QEMU variant: the PMIC window points at RAM; every read is 0 before the
# write, so the expected trace is fully determined, and the byte at +0x18B
# (and the word at +0x188, where it sits as byte 3) is checked directly in
# memory as well.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_reason2.XXXXXX)
mkdir -p artifacts

echo "== assemble"
# device build: real bases, trace ON (the whole point of v2)
aarch64-linux-gnu-as \
  --defsym PMIC_BASE=0xfff34000 \
  --defsym TRACE_BASE=0x348c0000 --defsym WITH_TRACE=1 \
  -o "$WORK/device.o" ane_reason2_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym PMIC_BASE=0x42006000 \
  --defsym TRACE_BASE=0x42001000 --defsym WITH_TRACE=1 \
  -o "$WORK/qemu.o" ane_reason2_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu   payload: $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== disassembly: the byte store must be strb at +0x18B"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | grep -E "strb|smc" | head -4

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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-reason2-probe.img --gzip | head -3

echo
echo "== QEMU check: trace = [step, value] x9; window byte and word"
python3 - "$WORK/qemu.Image" <<'PY'
import json, re, select, struct, subprocess, sys, time

expected = struct.pack("<18I",
    1, 0x0,
    2, 0x0,
    3, 0x0,
    4, 0x0,
    5, 0x0,
    6, 0x0,
    7, 0x0,
    8, 0x01,
    9, 0x01000000)

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
    got = dump(0x42001000, 72)
    if got[:72] == expected[:72]:
        break
byte = dump(0x4200618B, 1)
word = dump(0x42006188, 4)
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

ok_trace = got[:72] == expected[:72]
ok_byte = byte[:1] == b"\x01"
ok_word = word[:4] == b"\x00\x00\x00\x01"
print(f"  trace expected: {expected.hex(' ')}")
print(f"  trace got     : {got[:72].hex(' ')}")
print(f"  window +0x18B : {' '.join(f'{b:02x}' for b in byte[:1])}  (want 01)")
print(f"  window +0x188 : {' '.join(f'{b:02x}' for b in word[:4])}  (want 00 00 00 01)")
print()
if ok_trace and ok_byte and ok_word:
    print("  PASS: 9 traced reads/writes exact; the reason byte lands and reads back")
else:
    print("  FAIL: see above")
sys.exit(0 if (ok_trace and ok_byte and ok_word) else 1)
PY
echo "REASON2_BUILD_EXIT=$?"
