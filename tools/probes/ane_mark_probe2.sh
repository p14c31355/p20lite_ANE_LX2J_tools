#!/bin/bash
# Build mark probe v2 (three zones) and prove it writes all three records.
#
# Same discipline as v1: assemble twice with the window base as a --defsym, run
# the emulated variant, read the three zones back out of the guest and compare.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_probe2.XXXXXX)
mkdir -p artifacts

echo "== assemble"
for variant in device qemu; do
  case "$variant" in
    device) WINDOW=0x34800000 ;;
    qemu)   WINDOW=0x400e0000 ;;
  esac
  aarch64-linux-gnu-as --defsym WINDOW=$WINDOW -o "$WORK/$variant.o" ane_mark_probe2.S
  aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/$variant.elf" "$WORK/$variant.o"
  aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/$variant.elf" "$WORK/$variant.payload"
  echo "  $variant: WINDOW=$WINDOW payload=$(stat -c %s "$WORK/$variant.payload") bytes"
done
echo
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | sed -n '/<_start>:/,+14p'

echo
echo "== build Images (64-byte arm64 header, as the port's own)"
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
print("  built both Images")
PY

echo
echo "== package (gzip + raw)"
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-mark2.img --gzip | head -3
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-mark2-raw.img >/dev/null

echo
echo "== QEMU self-check (three zones)"
python3 - "$WORK/qemu.Image" <<'PY'
import json, select, struct, subprocess, sys, time

image = sys.argv[1]
SIG = 0x43474244
DMESG = b"====0.000000000\nFULLERENE-ANE-PROBE-DMESG\n"
CONSOLE = b"====0.000000000\nFULLERENE-ANE-PROBE-CONSOLE\n"
PMSG = b"\n001:E"
ZONES = [("dmesg  slot 0", 0x400E0000, DMESG),
         ("console zone ", 0x40140000, CONSOLE),
         ("pmsg    zone ", 0x401C0000, PMSG)]

def blob(text):
    return struct.pack("<III", SIG, 0, len(text)) + text

proc = subprocess.Popen(
    ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a53", "-m", "2G",
     "-display", "none", "-serial", "none", "-qmp", "stdio", "-kernel", image],
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

def read_zone(addr):
    reply = qmp({"execute": "human-monitor-command",
                 "arguments": {"command-line": f"xp /64bx {addr:#x}"}})
    text = (reply or {}).get("return", "")
    import re
    return bytes(int(t, 16) for t in re.findall(r"0x([0-9a-fA-F]{2})\b", text))

qmp({"execute": "qmp_capabilities"})
time.sleep(3)
ok = True
for name, addr, expect_text in ZONES:
    got = read_zone(addr)
    want = blob(expect_text)
    match = got[:len(want)] == want
    ok = ok and match
    print(f"  {name} {addr:#x}: {'PASS' if match else 'FAIL'}")
    if not match:
        print(f"    expected: {want[:40].hex(' ')}")
        print(f"    got     : {got[:40].hex(' ')}")
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()
sys.exit(0 if ok else 1)
PY

echo
ls -la artifacts/fullerene-ane-mark2*.img
