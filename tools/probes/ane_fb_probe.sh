#!/bin/bash
# Build the framebuffer probe and prove the fill in QEMU before the device.
#
# The emulated variant fills a 1 MiB RAM window with the same instruction
# sequence. The check dumps the first word, the last word, and the word just
# past the end: the first two must be the colour, the third must still be zero -
# that catches both a wrong colour and an off-by-one overrun.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_fbprobe.XXXXXX)
mkdir -p artifacts
COLOR=0xFF00FF00          # saturated green in ABGR8888; magenta in RGBA - either way, unmistakable

echo "== assemble"
aarch64-linux-gnu-as \
  --defsym FB_BASE=0x31000000 --defsym FB_SIZE=0x1a40000 --defsym COLOR=$COLOR \
  --defsym SPIN_HOLD=0x60000000 --defsym HOLD_REPEATS=12 --defsym WITH_SMC=1 \
  -o "$WORK/device.o" ane_fb_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym FB_BASE=0x43000000 --defsym FB_SIZE=0x100000 --defsym COLOR=$COLOR \
  --defsym SPIN_HOLD=0x100000 --defsym HOLD_REPEATS=1 --defsym WITH_SMC=0 \
  -o "$WORK/qemu.o" ane_fb_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu   payload: $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== disassembly (the fill loop must use the exact bounds)"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | sed -n '/<_start>:/,+16p'

echo
echo "== build the Linux arm64 Image + package"
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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-fb-probe.img --gzip | head -3

echo
echo "== QEMU check: fill 1 MiB, verify first/last word + no overrun"
python3 - "$WORK/qemu.Image" <<'PY'
import json, re, select, struct, subprocess, sys, time

image = sys.argv[1]
color = struct.pack("<I", 0xFF00FF00)

proc = subprocess.Popen(
    ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a53", "-m", "2G",
     "-display", "none", "-serial", "none", "-qmp", "stdio", "-kernel", image],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

def qmp(obj, timeout=15):
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

def xp(addr, count):
    reply = qmp({"execute": "human-monitor-command",
                 "arguments": {"command-line": f"xp /{count}bx {addr}"}})
    text = (reply or {}).get("return", "")
    return bytes(int(t, 16) for t in re.findall(r"0x([0-9a-fA-F]{2})\b", text))

qmp({"execute": "qmp_capabilities"})
time.sleep(3)
first = xp("0x43000000", 4)
last = xp("0x430ffffc", 4)
past = xp("0x43100000", 4)
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

print(f"  first word : {first.hex(' ')}  (want {color.hex(' ')})")
print(f"  last word  : {last.hex(' ')}   (want {color.hex(' ')})")
print(f"  past end   : {past.hex(' ')}   (want 00 00 00 00)")
ok = first == color and last == color and past == b"\x00\x00\x00\x00"
if ok:
    print("  PASS: the fill covers exactly [base, base+size) with the colour")
    sys.exit(0)
print("  FAIL: fill mismatch")
sys.exit(1)
PY

echo
echo "== results"
ls -la artifacts/fullerene-ane-fb-probe.img
echo
echo "On the device: the whole 27.5 MiB graphic region becomes solid colour,"
echo "stays for ~25 s, then the PSCI reset is attempted. Expected visible story"
echo "if the loader entered us: colour -> logo -> colour -> logo (a loop)."
