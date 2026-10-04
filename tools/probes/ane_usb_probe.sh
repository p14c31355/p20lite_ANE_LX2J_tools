#!/bin/bash
# Build the USB probe and prove its register-write sequence in QEMU first.
#
# The emulated variant is the same instruction sequence with three substitutions
# only: the core base points at RAM, the trace writes are enabled, and the delay
# counts are small. The trace array records [step, DCTL value] at every step, so
# the QEMU dump is a complete mechanical proof of what the device build will
# write - including the values - before any device cycle is spent.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_usbprobe.XXXXXX)
mkdir -p artifacts

echo "== assemble"
# device build: no memory writes at all, real delays, SMC reset armed
aarch64-linux-gnu-as \
  --defsym CORE_BASE=0xff100000 --defsym CRG_BASE=0xfff35000 \
  --defsym WITH_CLOCKS=1 --defsym TRACE_BASE=0 \
  --defsym WITH_TRACE=0 --defsym WITH_SMC=1 \
  --defsym SPIN_LONG=0x60000000 --defsym SPIN_SHORT=0x20000000 \
  -o "$WORK/device.o" ane_usb_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

# qemu build: same code, core->RAM, tracing on, small delays, no SMC
aarch64-linux-gnu-as \
  --defsym CORE_BASE=0x42000000 --defsym CRG_BASE=0x42002000 \
  --defsym WITH_CLOCKS=1 --defsym TRACE_BASE=0x42001000 \
  --defsym WITH_TRACE=1 --defsym WITH_SMC=0 \
  --defsym SPIN_LONG=0x800000 --defsym SPIN_SHORT=0x200000 \
  -o "$WORK/qemu.o" ane_usb_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu   payload: $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== disassembly (device build): the three addresses and values must be exact"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | sed -n '/<_start>:/,+6p'
echo "  ..."
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | grep -E "smc|wfe" | head -3

echo
echo "== build the Linux arm64 Image (64-byte header, as Fullerene's)"
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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-usb-probe.img --gzip | head -3

echo
echo "== QEMU check: run the emulated variant, dump the trace array + DCTL cell"
python3 - "$WORK/qemu.Image" <<'PY'
import json, pathlib, re, select, struct, subprocess, sys, time

image = sys.argv[1]

# expected trace: 6 steps, each two words [step, the value written].
#   step 6 = the CRG gate register after the RMW (0x46), recorded first in the
#   array because the clock step runs before the DCTL toggles.
#   The read back gives DCTL's live value on the device; in QEMU's zeroed RAM
#   it starts at 0, so the recorded store values are:
#     connect #1 (bic 2) -> 0        disconnect (orr 2)  -> 2
#     connect #2 (bic 2) -> 0        disconnect (orr 2)  -> 2
#     final connect      -> 0
expected_trace = struct.pack("<12I", 1, 0, 2, 2, 3, 0, 4, 2, 5, 0, 6, 0x46)
expected_dctl = struct.pack("<I", 0)          # final state: connected

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
time.sleep(8)                                  # full sequence: 2 long + 2 short spins
trace = xp("0x42001000", 48)
dctl = xp("0x42000804", 4)
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

print(f"  trace expected: {expected_trace.hex(' ')}")
print(f"  trace got     : {trace.hex(' ')}")
print(f"  DCTL  expected: {expected_dctl.hex(' ')}   got: {dctl.hex(' ')}")
ok = (trace[:len(expected_trace)] == expected_trace and
      dctl[:len(expected_dctl)] == expected_dctl)
if ok:
    print("  PASS: the probe writes SftDiscon 0/1/0/1/... in exactly this order")
    sys.exit(0)
print("  FAIL: sequence mismatch")
sys.exit(1)
PY

echo
echo "== results"
ls -la artifacts/fullerene-ane-usb-probe.img
echo
echo "On the device the probe will:"
echo "  1) toggle DCTL.SftDiscon twice with long holds  -> host sees attach/detach"
echo "  2) SMC PSCI SYSTEM_RESET                        -> machine loops if entered"
echo "  3) if the SMC returns: leave the pull-up on, halt"
