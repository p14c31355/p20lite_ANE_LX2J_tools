#!/bin/bash
# Build the L1d USB probe and prove its register sequence in QEMU first.
#
# l1d = l1c + a device-side trace (l1c ran with tracing off, so its on-device
# run left no record beyond "no attach on the host"), the AP PPLL0 enable, and
# post-attach readbacks. The device trace target 0x348c0000 sits inside the
# reserved pstore window - the same region the earlier pstore mark probes
# proved survives a reset - so a follow-up probe (or the visual channel, once
# the RCH track lands) can read it.
#
# The emulated variant retargets every base into QEMU RAM and turns on the
# trace, so the dump is a complete mechanical proof of the writes the device
# build will perform. On the device the read-modify-write steps read real
# register values, so only the OR-ed bits are identical - that is why the
# QEMU check pins the emulated starting values (zeroed RAM) and the device run
# is judged by the host seeing an attach.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_usb_l1.XXXXXX)
mkdir -p artifacts

echo "== assemble"
# device build: the real bases, no trace, hang (no SMC) so the attach is stable
aarch64-linux-gnu-as \
  --defsym CORE_BASE=0xff100000 --defsym CRG_BASE=0xfff35000 \
  --defsym PCTRL_BASE=0xe8a09000 --defsym AHBIF_BASE=0xff200000 \
  --defsym WITH_ABB=1 --defsym PMIC_BASE=0xfff34000 --defsym SCTRL_BASE=0xfff0a000 \
  --defsym WITH_CORE=1 --defsym PHY_BASE=0xfe000000 \
  --defsym TRACE_BASE=0x348c0000 --defsym WITH_TRACE=1 --defsym WITH_SMC=0 \
  --defsym SPIN_US=0x8000 --defsym SPIN_MS=0x80000 --defsym SPIN_LONG=0x20000000 \
  -o "$WORK/device.o" ane_usb_l1d_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"
# also build the SMC-loop variant for when a live loop is wanted
aarch64-linux-gnu-as \
  --defsym CORE_BASE=0xff100000 --defsym CRG_BASE=0xfff35000 \
  --defsym PCTRL_BASE=0xe8a09000 --defsym AHBIF_BASE=0xff200000 \
  --defsym WITH_ABB=1 --defsym PMIC_BASE=0xfff34000 --defsym SCTRL_BASE=0xfff0a000 \
  --defsym WITH_CORE=1 --defsym PHY_BASE=0xfe000000 \
  --defsym TRACE_BASE=0x348c0000 --defsym WITH_TRACE=1 --defsym WITH_SMC=1 \
  --defsym SPIN_US=0x8000 --defsym SPIN_MS=0x80000 --defsym SPIN_LONG=0x60000000 \
  -o "$WORK/loop.o" ane_usb_l1d_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/loop.elf" "$WORK/loop.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/loop.elf" "$WORK/loop.payload"
echo "  loop   payload: $(stat -c %s "$WORK/loop.payload") bytes"

# qemu build: every base into its own RAM page, tracing on, short delays
aarch64-linux-gnu-as \
  --defsym CORE_BASE=0x42000000 --defsym CRG_BASE=0x42003000 \
  --defsym PCTRL_BASE=0x42004000 --defsym AHBIF_BASE=0x42005000 \
  --defsym WITH_ABB=1 --defsym PMIC_BASE=0x42006000 --defsym SCTRL_BASE=0x42007000 \
  --defsym PHY_BASE=0x42008000 \
  --defsym WITH_CORE=1 \
  --defsym TRACE_BASE=0x42001000 --defsym WITH_TRACE=1 --defsym WITH_SMC=0 \
  --defsym SPIN_US=0x10000 --defsym SPIN_MS=0x10000 --defsym SPIN_LONG=0x10000 \
  -o "$WORK/qemu.o" ane_usb_l1d_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu   payload: $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== disassembly (device build): spot-check the five key writes"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | grep -E "str\s+w10, \[x1[23]" | head -12

echo
echo "== build the Linux arm64 Images (64-byte header, as Fullerene's)"
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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-usb-l1d.img --gzip | head -3
python3 mkane_bootimg.py "$WORK/loop.Image" artifacts/fullerene-ane-usb-l1d-loop.img --gzip | head -3

echo
echo "== QEMU check: run the emulated variant, dump the trace array"
python3 - "$WORK/qemu.Image" <<'PY'
import json, pathlib, re, select, struct, subprocess, sys, time

image = sys.argv[1]

# expected trace: entries live at slot (step-1), so the abb step (11, which
# runs FIRST) lands in slot 10 at the end of the array. Each entry is
# [step, the value written]; QEMU's RAM starts at 0, so the read-modify-write
# steps show exactly the OR-ed bits:
#   1 CRG+0x40 clocks        0x46
#   2 PCTRL+0x64 abb         0x05000000
#   3 CRG+0x94 adp|32k|mux|ahbif 0x08004C00
#   4 AHBIF+0x00 ctrl0       0x14
#   5 AHBIF+0x0C ctrl3       0x06b866db
#   6 CRG+0x94 |= phypor     0x08006C00
#   7 CRG+0x94 |= phy        0x08007C00
#   8 CRG+0x94 |= otg        0x08007E00
#   9 AHBIF+0x08 ctrl2       0x0C
#  10 DCTL sftdiscon clear   0x00
#  11 abb gate: sctrl+0x43C AP_ABB_EN set    0x1
#  12 GUSBCFG force-device|utmi8  0x40000000
#  13 DCFG devspd high speed      0x0
#  14 GUSBCFG re-write after the soft reset 0x40000000
#  15 PPLL0 pre-state (RAM 0)     0x0
#  16 PPLL0 post (EN set, no lock in QEMU RAM) 0x1
#  17..20 USB2PHY reads at 0xfe000000+0/4/8/C 0x0 (RAM)
#  21..24 GUSBCFG/DCFG/DCTL/GINTSTS read back 0x40000000/0x0/0x0/0x0
expected = struct.pack("<48I",
    1, 0x46,
    2, 0x05000000,
    3, 0x08004C00,
    4, 0x14,
    5, 0x06B866DB,
    6, 0x08006C00,
    7, 0x08007C00,
    8, 0x08007E00,
    9, 0x0C,
    10, 0x00,
    11, 0x1,
    12, 0x40000000,
    13, 0x0,
    14, 0x40000000,
    15, 0x0,
    16, 0x1,
    17, 0x0,
    18, 0x0,
    19, 0x0,
    20, 0x0,
    21, 0x40000000,
    22, 0x0,
    23, 0x0,
    24, 0x0)

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
# Poll until the trace fills: the device-style delay loops are long sequences
# in TCG, so a fixed sleep is unreliable.
t0 = time.time()
got = b""
while time.time() - t0 < 120:
    time.sleep(3)
    got = dump(0x42001000, 192)
    if got[:192] == expected[:192]:
        break
pmic = dump(0x42006100, 32)
sctrl = dump(0x4200743C, 8)
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

ok_trace = got[:192] == expected[:192]
ok_pmic = len(pmic) >= 16 and pmic[15] == 0x01
ok_sctrl = len(sctrl) >= 4 and sctrl[0:4] == b"\x01\x00\x00\x00"
print(f"  trace expected: {expected[:192].hex(' ')}")
print(f"  trace got     : {got[:192].hex(' ')}")
print(f"  pmic  +0x10F  : {' '.join(f'{b:02x}' for b in pmic[14:18])}  (want .. 01 .. ..)")
print(f"  sctrl +0x43C  : {' '.join(f'{b:02x}' for b in sctrl[0:4])}  (want 01 00 00 00)")
print()
if ok_trace:
    print("  PASS: all 24 steps write exactly the intended values")
else:
    print("  FAIL: trace mismatch above")
print("  abb writes: " + ("PASS" if (ok_pmic and ok_sctrl) else "FAIL"))
sys.exit(0 if (ok_trace and ok_pmic and ok_sctrl) else 1)
PY
echo "L1_BUILD_EXIT=$?"
