#!/bin/bash
# Build the reason probe and prove its write in QEMU first.
#
# QEMU variant: the PMIC window points at RAM, and the trace records both the
# step marker and the byte read back from the retargeted window - which proves
# the store landed and is byte-readable, exactly what the device build needs.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_reason.XXXXXX)
mkdir -p artifacts

echo "== assemble"
aarch64-linux-gnu-as \
  --defsym PMIC_BASE=0xfff34000 --defsym TRACE_BASE=0 --defsym WITH_TRACE=0 \
  -o "$WORK/device.o" ane_reason_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym PMIC_BASE=0x42006000 --defsym TRACE_BASE=0x42001000 --defsym WITH_TRACE=1 \
  -o "$WORK/qemu.o" ane_reason_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu payload: $(printf '%s' $(stat -c %s "$WORK/qemu.payload")) bytes"

echo
echo "== disassembly: the PMIC write must be a byte store at +0x18B"
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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-reason-probe.img --gzip | head -3

echo
echo "== QEMU check: the byte must be at 0x42006000+0x18B"
python3 - "$WORK/qemu.Image" <<'PY'
import json, pathlib, re, select, struct, subprocess, sys, time

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

qmp({"execute": "qmp_capabilities"})
time.sleep(3)
reply = qmp({"execute": "human-monitor-command",
             "arguments": {"command-line": "xp /8bx 0x4200618b"}})
text = (reply or {}).get("return", "")
got = bytes(int(t, 16) for t in re.findall(r"0x([0-9a-fA-F]{2})\b", text))
reply2 = qmp({"execute": "human-monitor-command",
              "arguments": {"command-line": "xp /8bx 0x42001000"}})
text2 = (reply2 or {}).get("return", "")
got2 = bytes(int(t, 16) for t in re.findall(r"0x([0-9a-fA-F]{2})\b", text2))
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

want = b"\x01" + b"\x00" * 7
ok1 = got[0:8] == want
print(f"  window byte at +0x18B: {got[:8].hex(' ')}  (want 01 00 00 00 00 00 00 00)")
ok2 = got2[0:8] == struct.pack("<II", 1, 1)
print(f"  trace [step,readback] : {got2[:8].hex(' ')}  (want 01 00 00 00 01 00 00 00)")
print()
print("  PASS: the reason byte is written and reads back" if (ok1 and ok2) else "  FAIL")
sys.exit(0 if (ok1 and ok2) else 1)
PY
echo "REASON_BUILD_EXIT=$?"
