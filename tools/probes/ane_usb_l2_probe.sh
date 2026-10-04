#!/bin/bash
# Build the L2 USB probe (EP0 responder) and prove everything provable in QEMU.
#
# QEMU cannot model the DWC2, so the responder loop simply spins there. What
# the QEMU run does prove: the whole register sequence still writes exactly
# the intended values (trace dump), and the code reaches the responder. The
# descriptor tables are checked in the binary, and the movz/movk base pairs
# are checked mechanically. The USB behaviour itself can only be judged by a
# host seeing the enumeration (12d1:0001 appears in lsusb).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_usb_l2.XXXXXX)
mkdir -p artifacts

echo "== assemble"
aarch64-linux-gnu-as \
  --defsym CORE_BASE=0xff100000 --defsym CRG_BASE=0xfff35000 \
  --defsym PCTRL_BASE=0xe8a09000 --defsym AHBIF_BASE=0xff200000 \
  --defsym WITH_ABB=1 --defsym PMIC_BASE=0xfff34000 --defsym SCTRL_BASE=0xfff0a000 \
  --defsym TRACE_BASE=0 --defsym WITH_TRACE=0 --defsym WITH_SMC=0 \
  --defsym SPIN_US=0x8000 --defsym SPIN_MS=0x80000 --defsym SPIN_LONG=0x20000000 \
  -o "$WORK/device.o" ane_usb_l2_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"
aarch64-linux-gnu-as \
  --defsym CORE_BASE=0xff100000 --defsym CRG_BASE=0xfff35000 \
  --defsym PCTRL_BASE=0xe8a09000 --defsym AHBIF_BASE=0xff200000 \
  --defsym WITH_ABB=1 --defsym PMIC_BASE=0xfff34000 --defsym SCTRL_BASE=0xfff0a000 \
  --defsym TRACE_BASE=0 --defsym WITH_TRACE=0 --defsym WITH_SMC=1 \
  --defsym SPIN_US=0x8000 --defsym SPIN_MS=0x80000 --defsym SPIN_LONG=0x60000000 \
  -o "$WORK/loop.o" ane_usb_l2_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/loop.elf" "$WORK/loop.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/loop.elf" "$WORK/loop.payload"
echo "  loop   payload: $(stat -c %s "$WORK/loop.payload") bytes"
aarch64-linux-gnu-as \
  --defsym CORE_BASE=0x42000000 --defsym CRG_BASE=0x42003000 \
  --defsym PCTRL_BASE=0x42004000 --defsym AHBIF_BASE=0x42005000 \
  --defsym WITH_ABB=1 --defsym PMIC_BASE=0x42006000 --defsym SCTRL_BASE=0x42007000 \
  --defsym TRACE_BASE=0x42010000 --defsym WITH_TRACE=1 --defsym WITH_SMC=0 \
  --defsym SPIN_US=0x10000 --defsym SPIN_MS=0x10000 --defsym SPIN_LONG=0x10000 \
  -o "$WORK/qemu.o" ane_usb_l2_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu   payload: $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== static checks: movz/movk base pairs (the RCH probe shipped a bug here)"
bash tools/audit_movz_movk.sh "$WORK/device.elf" || { echo "AUDIT FAILED"; exit 1; }

echo
echo "== static check: descriptor bytes present in the device payload"
python3 - "$WORK/device.payload" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]).read_bytes()
dev = bytes.fromhex("1201000200000040d1120100010000000001")
cfg = bytes.fromhex("0902120001010080320904000000ff000000")
ok = dev in p and cfg in p
print(f"  device descriptor found : {dev in p}")
print(f"  config descriptor found : {cfg in p}")
sys.exit(0 if ok else 1)
PY

echo
echo "== build the Linux arm64 Images (same 64-byte header as L1)"
python3 - "$WORK" <<'PY'
import struct, sys, pathlib
work = pathlib.Path(sys.argv[1])
for variant in ("device", "loop", "qemu"):
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
echo "== package the device images (gzip)"
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-usb-l2.img --gzip | head -3
python3 mkane_bootimg.py "$WORK/loop.Image" artifacts/fullerene-ane-usb-l2-loop.img --gzip | head -3

echo
echo "== QEMU check: run the emulated variant, dump the trace array"
python3 - "$WORK/qemu.Image" <<'PY'
import json, pathlib, re, select, struct, subprocess, sys, time

image = sys.argv[1]

# expected trace, slots in step order (the abb step 11 runs first):
#   1 CRG+0x40 clocks           0x46
#   2 PCTRL+0x64 abb            0x05000000
#   3 CRG+0x94 resets           0x08004C00
#   4 AHBIF+0x00 ctrl0          0x14
#   5 AHBIF+0x0C ctrl3          0x06b866db
#   6 CRG+0x94|=phypor          0x08006C00
#   7 CRG+0x94|=phy             0x08007C00
#   8 CRG+0x94|=otg             0x08007E00
#   9 AHBIF+0x08 ctrl2          0x0C
#  10 DCTL sftdiscon clear      0x100  (cgnpinnak set at step 15)
#  11 abb AP_ABB_EN             0x1
#  12 GUSBCFG pre-reset         0x40000000
#  13 DCFG devspd               0x0
#  14 GUSBCFG post-reset        0x40000000
#  15 DCTL cgnpinnak            0x100
#  16 DIEPCTL0 mps=64           0x0
#  17 responder entered         0x0
expected = struct.pack("<34I",
    1, 0x46,
    2, 0x05000000,
    3, 0x08004C00,
    4, 0x14,
    5, 0x06B866DB,
    6, 0x08006C00,
    7, 0x08007C00,
    8, 0x08007E00,
    9, 0x0C,
    10, 0x100,
    11, 0x1,
    12, 0x40000000,
    13, 0x0,
    14, 0x40000000,
    15, 0x100,
    16, 0x0,
    17, 0x0)

proc = subprocess.Popen(
    ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a53", "-m", "2G",
     "-display", "none", "-serial", "none", "-qmp", "stdio",
     "-kernel", image],
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
while time.time() - t0 < 120:
    time.sleep(3)
    got = dump(0x42010000, 136)
    if got[:136] == expected[:136]:
        break
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

ok_trace = got[:136] == expected[:136]
print(f"  trace expected: {expected[:136].hex(' ')}")
print(f"  trace got     : {got[:136].hex(' ')}")
print()
if ok_trace:
    print("  PASS: the responder preamble writes exactly the intended values")
    print("        (the responder itself cannot run in QEMU: no DWC2 model)")
else:
    print("  FAIL: trace mismatch above")
sys.exit(0 if ok_trace else 1)
PY

echo
echo "== results"
ls -l artifacts/fullerene-ane-usb-l2.img artifacts/fullerene-ane-usb-l2-loop.img
