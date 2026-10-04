#!/bin/bash
# QEMU proof that the ANE step marks execute, in order, writing "12345..."
# (and, since the Rust entry marks exist, through '6' before the QEMU-only
# console fault stops the boot). The fault itself is the second assertion:
# the early park vectors take it, append the fault byte 'F' to the scratch
# and park - so the retargeted scratch must read "123456F".
#
# The marks write to the step-mark scratch (0x348df000, the ramoops console
# zone's unused tail). In QEMU virt that address lies inside the PCIe MMIO
# window and is silently discarded - so a plain QEMU run cannot see them.
# This script temporarily retargets the scratch into QEMU RAM (0x42000000;
# one definition now - StepMarks::ADDRESS - and both users read it through
# the struct): the Rust const, the early-vector handler's movz/movk pair,
# and the address half of the handler's build-time assert. It builds, runs
# the kernel, reads the bytes back over QMP (the same method the mark probes
# used), then restores the source byte-for-byte and rebuilds the device image.
set -u
cd "$(dirname "$0")"
FE=/home/placeless/dev/fullerene
ENTRY=$FE/fullerene-kernel/src/arch/aarch64/entry.rs
IMAGE=$FE/target/akee33290c7bc23734/aarch64-unknown-none/release/fullerene-kernel-aarch64.Image

cp "$ENTRY" /tmp/entry.rs.orig

echo "== retarget the scratch into QEMU RAM (0x42000000)"
sed -i 's/pub const ADDRESS: usize = 0x348d_f000;/pub const ADDRESS: usize = 0x4200_0000;/g' "$ENTRY"
sed -i 's/movz x19, #0xf000/movz x19, #0x0000/; s/movk x19, #0x348d, lsl #16/movk x19, #0x4200, lsl #16/' "$ENTRY"
sed -i 's/StepMarks::ADDRESS == 0x348d_f000/StepMarks::ADDRESS == 0x4200_0000/' "$ENTRY"
grep -n "const ADDRESS: usize" "$ENTRY"
grep -n "movk x19" "$ENTRY"

echo "== build the retargeted image"
( cd "$FE" && cargo run -q -p flasks -- build --arch aarch64 --platform ane >/dev/null 2>&1 )
rc=$?
if [ $rc -ne 0 ]; then
  echo "build failed (rc=$rc) - restoring source"
  cp /tmp/entry.rs.orig "$ENTRY"
  exit 1
fi
cp "$IMAGE" /tmp/marks_qemu.Image
ls -la /tmp/marks_qemu.Image

echo "== restore the source and rebuild the device image"
cp /tmp/entry.rs.orig "$ENTRY"
if diff -q /tmp/entry.rs.orig "$ENTRY" >/dev/null; then echo "entry.rs identical to the original"; else echo "RESTORE FAILED"; exit 1; fi
grep -n "const ADDRESS: usize" "$ENTRY"
( cd "$FE" && cargo run -q -p flasks -- build --arch aarch64 --platform ane >/dev/null 2>&1 ) && echo "device image rebuilt"

echo
echo "== QEMU run + QMP readback of 0x42000000 (magic, count, mark bytes)"
python3 - <<'PY'
import json, re, select, subprocess, sys, time

SCRATCH = 0x42000000
proc = subprocess.Popen(
    ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a53", "-m", "2G",
     "-display", "none", "-serial", "none", "-qmp", "stdio",
     "-kernel", "/tmp/marks_qemu.Image"],
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
time.sleep(4)
reply = qmp({"execute": "human-monitor-command",
             "arguments": {"command-line": f"xp /32bx {SCRATCH:#x}"}})
text = (reply or {}).get("return", "")
got = bytes(int(t, 16) for t in re.findall(r"0x([0-9a-fA-F]{2})\b", text))
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

want_magic = b"ANEM"
ok_magic = got[0:4] == want_magic
count = int.from_bytes(got[4:8], "little")
marks = got[8:8 + min(count, 16)]
ok_prefix = marks[:5] == b"12345"
ok_entry = marks[5:6] == b"6"
ok_fault = marks[6:7] == b"F"
print(f"  magic : {got[0:4]!r}  (want b'ANEM')")
print(f"  count : {count}")
print(f"  marks : {marks!r}  (want b'123456F': entry marks, then the early-vector fault byte)")
print()
print(f"  magic        : {'PASS' if ok_magic else 'FAIL'}")
print(f"  '12345'      : {'PASS' if ok_prefix else 'FAIL'}")
print(f"  '6' present  : {'PASS' if ok_entry else 'FAIL'}")
print(f"  'F' (fault)  : {'PASS' if ok_fault else 'FAIL (early-vector handler did not run)'}")
sys.exit(0 if (ok_magic and ok_prefix and ok_entry and ok_fault) else 1)
PY
echo "PROOF_EXIT=$?"
