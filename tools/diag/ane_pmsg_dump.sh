#!/bin/bash
# Build the pmsg dumper probe and prove it in QEMU against a seeded zone.
#
# Seeded state (WITH_SEED writes all of it): header {sig, 0, 5} + "hello\x01",
# trace = 24 words 0x100..0x117, marks = "ANEM" + count 2 + "ab".
# Expected result at the zone: size 5 -> 133, and the 128-byte record at
# +12+5 exactly: marker + the trace words + the marks block.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_pmsg.XXXXXX)
mkdir -p artifacts

echo "== assemble"
aarch64-linux-gnu-as \
  --defsym PMSG_BASE=0x348E0000 --defsym TRACE_BASE=0x348c0000 \
  --defsym MARKS_BASE=0x348DF000 --defsym PMSG_MAX=0x1F000 \
  --defsym WITH_SEED=0 \
  -o "$WORK/device.o" ane_pmsg_dump.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym PMSG_BASE=0x42000000 --defsym TRACE_BASE=0x42001000 \
  --defsym MARKS_BASE=0x42002000 --defsym PMSG_MAX=0x1F000 \
  --defsym WITH_SEED=1 \
  -o "$WORK/qemu.o" ane_pmsg_dump.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu payload:   $(stat -c %s "$WORK/qemu.payload") bytes"

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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-pmsg-dump.img --gzip | head -3

echo
echo "== QEMU check: append + size commit exact"
python3 - "$WORK/qemu.Image" <<'PY'
import json, re, select, struct, subprocess, sys, time

trace = b"".join(struct.pack("<I", 0x100 + i) for i in range(24))
marks = struct.pack("<II", 0x4D454E41, 2) + b"ab" + bytes(14)
record = b"ANEPv1->" + trace + marks
want_head = struct.pack("<III", 0x43474244, 0, 5 + 128)

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
time.sleep(3)
got_head = dump(0x42000000, 12)
got_rec = dump(0x42000000 + 12 + 5, 128)
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

ok_head = got_head == want_head
ok_rec = got_rec == record
print(f"  header got : {got_head.hex(' ')}")
print(f"  header want: {want_head.hex(' ')}")
print(f"  record match: {ok_rec}")
if not ok_rec:
    print(f"  record got : {got_rec[:40].hex(' ')} ...")
    print(f"  record want: {record[:40].hex(' ')} ...")
print()
if ok_head and ok_rec:
    print("  PASS: append at the right offset, exact bytes, size committed")
else:
    print("  FAIL: see above")
sys.exit(0 if (ok_head and ok_rec) else 1)
PY
echo "PMSG_BUILD_EXIT=$?"
