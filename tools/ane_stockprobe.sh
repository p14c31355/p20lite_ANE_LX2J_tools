#!/bin/bash
# Build the "stock-payload probe": the stock kernel Image with our probe written
# only at the stock's own entry point.
#
# Why this shape: the LK boots the repacked stock fine but rejects (or at least
# never visibly runs) our tiny hand-made payloads. Rather than guess what it
# validates, this image IS the stock - same header, same 34 MB payload, same
# compressed size class - with one 200-byte window rewritten at 0x1660000,
# which is exactly where the stock's own code0 branches:
#
#     code0 (image byte 0):  b +0x1660000      <- stock's real entry
#     our probe at       :    0x1660000
#
# So whether the loader jumps to the image start (running code0) or computes
# the entry itself, the landing site is our code. The probe is the MMU-off
# framebuffer build: clear SCTLR.M if set, fill the graphic region with colour,
# hold ~40 s, then attempt the PSCI reset.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_stockprobe.XXXXXX)
mkdir -p artifacts

STOCK_IMAGE=firmware/ane_bootimg/stock_Image
ENTRY_OFF=0x1660000
COLOR=0xFF00FF00

echo "== assemble the probe (device + qemu variants, same source as fb2)"
aarch64-linux-gnu-as \
  --defsym FB_BASE=0x31000000 --defsym FB_SIZE=0x1a40000 --defsym COLOR=$COLOR \
  --defsym SPIN_HOLD=0x60000000 --defsym HOLD_REPEATS=18 --defsym WITH_SMC=1 \
  -o "$WORK/device.o" ane_fb_probe2.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device probe: $(stat -c %s "$WORK/device.payload") bytes"

aarch64-linux-gnu-as \
  --defsym FB_BASE=0x43000000 --defsym FB_SIZE=0x100000 --defsym COLOR=$COLOR \
  --defsym SPIN_HOLD=0x100000 --defsym HOLD_REPEATS=1 --defsym WITH_SMC=0 \
  -o "$WORK/qemu.o" ane_fb_probe2.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"

echo
echo "== patch the stock Image at the entry point (+0x$ENTRY_OFF)"
python3 - "$WORK" "$STOCK_IMAGE" <<'PY'
import pathlib, sys
work, stock = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
img = bytearray(stock.read_bytes())
off = 0x1660000
for variant in ("device", "qemu"):
    patched = bytearray(img)
    probe = (work / f"{variant}.payload").read_bytes()
    patched[off:off + len(probe)] = probe
    (work / f"{variant}.Image").write_bytes(bytes(patched))
    print(f"  {variant}: probe {len(probe)} B @ {off:#x}, image {len(patched):,} B")
# sanity: header untouched, and the first 4 bytes must still be `b +0x1660000`
head = (work / "device.Image").read_bytes()[:16]
print("  header now:", head.hex(" "))
assert head[:4] == bytes.fromhex("00805914"), "code0 changed - must stay the stock's branch"
print("  code0 still branches to +0x1660000")
PY

echo
echo "== package the device image (gzip + ANDROID!, same packager as the accepted repack)"
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-stockprobe.img --gzip | head -4
ls -la artifacts/fullerene-ane-stockprobe.img
echo
echo "== compare with the accepted repacked stock (shapes should match)"
ls -la firmware/ane_bootimg/repacked_stock.img firmware/kernel_stock.bin 2>/dev/null

echo
echo "== QEMU end-to-end: boot the patched Image (QEMU runs code0 -> our probe)"
python3 - "$WORK/qemu.Image" <<'PY'
import json, re, select, struct, subprocess, sys, time
image = sys.argv[1]
color = struct.pack("<I", 0xFF00FF00)
proc = subprocess.Popen(
    ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a53", "-m", "2G",
     "-display", "none", "-serial", "none", "-qmp", "stdio", "-kernel", image],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
def qmp(obj, timeout=20):
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
time.sleep(5)
first, last, past = xp("0x43000000", 4), xp("0x430ffffc", 4), xp("0x43100000", 4)
qmp({"execute": "quit"})
try: proc.wait(timeout=10)
except subprocess.TimeoutExpired: proc.kill()
print(f"  first: {first.hex(' ')}  last: {last.hex(' ')}  past: {past.hex(' ')}")
ok = first == color and last == color and past == b"\x00\x00\x00\x00"
print("  PASS: code0 -> stock entry point -> our probe ran in QEMU" if ok else "  FAIL")
sys.exit(0 if ok else 1)
PY
