#!/bin/bash
# Build the tiny mark probe and prove it works before any device is involved.
#
# Two builds of the same 30-instruction payload:
#   device (MARK_BASE = the ANE's pmsg zone 0x348e0000)  -> artifacts/fullerene-ane-mark.img
#   qemu   (MARK_BASE = emulated RAM     0x400e0000)     -> self-checked here
#
# The QEMU self-check is the interesting half: the emulated variant writes the
# record into QEMU's RAM, and `pmemsave` dumps exactly those bytes back. If the
# dump matches the expected 18 bytes, the same instruction sequence writes the
# same record on the device.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_probe.XXXXXX)
mkdir -p artifacts

echo "== assemble"
for variant in device qemu; do
  case "$variant" in
    device) BASE=0x348e0000 ;;
    qemu)   BASE=0x400e0000 ;;
  esac
  aarch64-linux-gnu-as --defsym MARK_BASE=$BASE -o "$WORK/$variant.o" ane_mark_probe.S
  aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/$variant.elf" "$WORK/$variant.o"
  aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/$variant.elf" "$WORK/$variant.payload"
  SZ=$(stat -c %s "$WORK/$variant.payload")
  echo "  $variant: MARK_BASE=$BASE payload=$SZ bytes"
done

echo
echo "== first instruction check (expect movz w9, #0x348e, lsl #16 = 0x52a691c9)"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | sed -n '/<_start>:/,+3p'

echo
echo "== build the Linux arm64 Image (64-byte header + payload)"
python3 - "$WORK" <<'PY'
import struct, sys, pathlib
work = pathlib.Path(sys.argv[1])
for variant in ("device", "qemu"):
    payload = (work / f"{variant}.payload").read_bytes()
    header = bytearray(64)
    struct.pack_into("<II", header, 0, 0x14000010, 0xD503201F)  # b +0x40 ; nop
    struct.pack_into("<Q", header, 8, 0x80000)                  # text_offset, as Fullerene's
    struct.pack_into("<Q", header, 16, 0x400000)                # image_size, as Fullerene's
    struct.pack_into("<Q", header, 24, 0x2)                     # flags, as Fullerene's
    header[0x38:0x3C] = b"ARM\x64"
    image = bytes(header) + payload
    out = work / f"{variant}.Image"
    out.write_bytes(image)
    print(f"  {variant}.Image: {len(image)} bytes  code0={struct.unpack_from('<I', image, 0)[0]:#010x} "
          f"magic={image[0x38:0x3C]!r}")
PY

echo
echo "== package (gzip + raw, same wrapper as Fullerene)"
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-mark.img --gzip
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-mark-raw.img
python3 mkane_bootimg.py "$WORK/qemu.Image" "$WORK/qemu-boot.img" --gzip >/dev/null

echo
echo "== QEMU self-check: run the emulated variant and dump the record back"
python3 - "$WORK/qemu.Image" "$WORK/dump.bin" <<'PY'
import json, pathlib, select, subprocess, sys, time

image, dump = sys.argv[1], sys.argv[2]
expected = bytes.fromhex("4442474300000000060000000a3030313a45")  # DBGC,0,6,"\n001:E"

proc = subprocess.Popen(
    ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a53", "-m", "2G",
     "-display", "none", "-serial", "none", "-qmp", "stdio",
     "-kernel", image],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)


def qmp(obj, timeout=10):
    """Send one QMP command and return its reply (or None on timeout)."""
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


qmp({"execute": "qmp_capabilities"})          # greeting is read inside
time.sleep(3)                                 # let the guest execute the stores first
# `xp` prints the bytes into the monitor reply, so nothing depends on HMP's
# filename handling (its parser rejects absolute paths - measured).
reply = qmp({"execute": "human-monitor-command",
             "arguments": {"command-line": "xp /64bx 0x400e0000"}})
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

text = (reply or {}).get("return", "")
print("  qemu said:", repr(text[:120]))
hexes = [int(tok, 16) for tok in __import__("re").findall(r"0x([0-9a-fA-F]{2})\b", text)]
got = bytes(hexes[:len(expected)])
print(f"  expected: {expected.hex(' ')}")
print(f"  got     : {got.hex(' ')}")
if got == expected:
    print("  PASS: the probe's instructions write the exact pstore record")
    sys.exit(0)
print("  FAIL: the dumped bytes do not match the expected record")
sys.exit(1)
PY

echo
echo "== results"
ls -la artifacts/fullerene-ane-mark.img artifacts/fullerene-ane-mark-raw.img
echo
echo "device probe: MARK_BASE=0x348e0000 (the ANE's pmsg zone)"
echo "expected record on the device after a power cycle: \\n001:E (size 6) at 0x348e0000"
