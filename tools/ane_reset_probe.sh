#!/bin/bash
# Build the PSCI reset probe and check it in QEMU before it touches a device.
#
# QEMU's virt machine honours PSCI SYSTEM_RESET, so with -no-reboot a correct
# probe makes QEMU *exit* instead of sitting in the halt loop. That difference
# is the whole check: exit == the SMC resets the machine; timeout == it does not.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_reset.XXXXXX)
mkdir -p artifacts

echo "== assemble"
aarch64-linux-gnu-as -o "$WORK/probe.o" ane_reset_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/probe.elf" "$WORK/probe.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/probe.elf" "$WORK/probe.payload"
aarch64-linux-gnu-objdump -d "$WORK/probe.elf" | sed -n '/<_start>:/,+8p'
echo "  payload: $(stat -c %s "$WORK/probe.payload") bytes"

echo
echo "== build the Image and package"
python3 - "$WORK" <<'PY'
import struct, pathlib, sys
work = pathlib.Path(sys.argv[1])
payload = (work / "probe.payload").read_bytes()
header = bytearray(64)
struct.pack_into("<II", header, 0, 0x14000010, 0xD503201F)
struct.pack_into("<Q", header, 8, 0x80000)
struct.pack_into("<Q", header, 16, 0x400000)
struct.pack_into("<Q", header, 24, 0x2)
header[0x38:0x3C] = b"ARM\x64"
(work / "probe.Image").write_bytes(bytes(header) + payload)
print(f"  probe.Image: {len(header) + len(payload)} bytes")
PY
python3 mkane_bootimg.py "$WORK/probe.Image" artifacts/fullerene-ane-reset.img --gzip | head -3

echo
echo "== QEMU check: the SMC must reset the machine (QEMU exits under -no-reboot)"
start=$(date +%s)
set +e
timeout 10 qemu-system-aarch64 -M virt -cpu cortex-a53 -m 2G -no-reboot \
  -display none -serial none -monitor none \
  -kernel "$WORK/probe.Image" >/dev/null 2>&1
rc=$?
set -e
elapsed=$(( $(date +%s) - start ))
echo "  qemu exit=$rc after ${elapsed}s (124 = still running when killed)"
if [ "$rc" -eq 124 ]; then
  echo "  FAIL: QEMU never reset - the SMC did not reach PSCI"
  exit 1
fi
echo "  PASS: the guest reset itself, so the SMC calls PSCI correctly"
ls -la artifacts/fullerene-ane-reset.img
