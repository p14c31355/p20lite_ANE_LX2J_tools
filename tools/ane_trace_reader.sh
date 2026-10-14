#!/bin/bash
# Build the trace reader and prove its scan/extract/emit in QEMU with seeded
# records first (the device ring is empty here, so without WITH_SEED the QEMU
# run would only prove that nothing crashes).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_reader.XXXXXX)
mkdir -p artifacts

echo "== assemble"
# device build: the real window bases, no seed
aarch64-linux-gnu-as \
  --defsym TRACE_BASE=0x348c0000 --defsym BOX_BASE=0x34800000 \
  --defsym MARKS_BASE=0x348df000 --defsym WITH_SEED=0 \
  -o "$WORK/device.o" ane_trace_reader.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym TRACE_BASE=0x42001000 --defsym BOX_BASE=0x42010000 \
  --defsym MARKS_BASE=0x42020000 --defsym WITH_SEED=1 \
  -o "$WORK/qemu.o" ane_trace_reader.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu   payload: $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== disassembly: the ring record stride must be 32"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | grep -E "add.*#(0x)?20|0x120" | head -4

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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-trace-reader.img --gzip | head -3

echo
echo "== QEMU check with seeded records"
python3 - "$WORK/qemu.Image" <<'PY'
import json, re, select, struct, subprocess, sys, time

# seeded: pair0 = steps1,2 (0x46, 0x05000000); pair7 = steps15,16 (0x04000001 each);
# pair11 = steps23,24 (0,0).  Emit order [1,2,3,4,5,10,12,14,15,16,21,23] gives:
want_marks = b"ANEM" + struct.pack("<I", 12) + bytes(
    [0x00, 0x05, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE, 0x04, 0x04, 0xEE, 0x00])

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
time.sleep(2)
marks = dump(0x42020000, len(want_marks))
table = dump(0x42001000, 24)   # the first three entries: (1,0x46),(2,0x05000000),(3?)
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

ok_marks = marks == want_marks
# entry 0 must be step 1 value 0x46; entry 1 step 2 value 0x05000000
ok_table = struct.unpack_from("<4I", table, 0) == (1, 0x46, 2, 0x05000000)
print(f"  marks got     : {marks.hex(' ')}")
print(f"  marks want    : {want_marks.hex(' ')}")
print(f"  table[0..1]   : {table[:16].hex(' ')}  (want 01 00 00 00 46 00 00 00 02 00 00 00 00 00 00 05)")
print()
if ok_marks and ok_table:
    print("  PASS: scan, extraction and emit all exact under seeded records")
else:
    print("  FAIL: see above")
sys.exit(0 if (ok_marks and ok_table) else 1)
PY
echo "READER_BUILD_EXIT=$?"
