#!/bin/bash
# Build the MMU-off framebuffer probe and check both halves in QEMU.
#
# The QEMU check is the same as for v1 (fill bounds + colour) with one
# addition: the MMU preamble must be a no-op on a machine that already boots
# with the MMU off, which is exactly how QEMU's -kernel entry works - so a
# passing v2 check also proves the preamble does not disturb a clean handoff.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_fbprobe2.XXXXXX)
mkdir -p artifacts
COLOR=0xFF00FF00

echo "== assemble"
aarch64-linux-gnu-as \
  --defsym FB_BASE=0x31000000 --defsym FB_SIZE=0x1a40000 --defsym COLOR=$COLOR \
  --defsym SPIN_HOLD=0x60000000 --defsym HOLD_REPEATS=18 --defsym WITH_SMC=1 \
  -o "$WORK/device.o" ane_fb_probe2.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym FB_BASE=0x43000000 --defsym FB_SIZE=0x100000 --defsym COLOR=$COLOR \
  --defsym SPIN_HOLD=0x100000 --defsym HOLD_REPEATS=1 --defsym WITH_SMC=0 \
  -o "$WORK/qemu.o" ane_fb_probe2.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"

echo
echo "== disassembly: the preamble must branch on CurrentEL and only clear M"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | sed -n '/<_start>:/,+20p'

echo
echo "== Image + package"
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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-fb2.img --gzip | head -3

echo
echo "== QEMU check: preamble is a no-op, fill is exact"
python3 - "$WORK/qemu.Image" <<'PY'
import json, re, select, struct, subprocess, sys, time
image = sys.argv[1]
color = struct.pack("<I", 0xFF00FF00)
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
time.sleep(3)
first, last, past = xp("0x43000000", 4), xp("0x430ffffc", 4), xp("0x43100000", 4)
qmp({"execute": "quit"})
try: proc.wait(timeout=10)
except subprocess.TimeoutExpired: proc.kill()
print(f"  first: {first.hex(' ')}  last: {last.hex(' ')}  past: {past.hex(' ')}")
ok = first == color and last == color and past == b"\x00\x00\x00\x00"
print("  PASS: preamble harmless, fill exact" if ok else "  FAIL")
sys.exit(0 if ok else 1)
PY

echo
echo "== results"
ls -la artifacts/fullerene-ane-fb2.img
echo "device readout: colour (~40 s) -> logo -> colour (loop) if entered+MMU was the blocker;"
echo "                colour then quiet if the SMC cannot reset; nothing at all if not entered."
