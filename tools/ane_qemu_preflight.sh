#!/bin/bash
# Host-side preflight: run the built ANE image on QEMU's generic ARM virt machine
# and ask where execution first touches a device address.
#
# QEMU does not model this board, and that is what makes the run useful: the
# PL011 the kernel inits at 0xfdf02000 does not exist there, so its first
# register write is *rejected*, and QEMU logs the address. As of 2026-10-03 the
# ANE build first opens the console's clock gate (CRG+0x20 = 0xfff35020), so
# that is the expected first rejected access; builds before the gate landed
# directly in the PL011 block. For execution to get
# that far, everything before it has to have completed without faulting - the
# entry stub, the static-PIE relocations, BSS zeroing, the Rust entry, and
# `blackbox::mark_entry` (whose own accesses land in QEMU's unassigned low
# memory, which is silently swallowed rather than rejected).
#
# So a pass here is: first rejected access at the CRG gate 0xfff35020 (or, for
# pre-gate builds, inside the PL011 block at 0xfdf020xx).
# It does not prove the mark wrote anything (QEMU discards those stores); it
# proves the code path up to the first device write executes.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
IMG=${1:?usage: ane_qemu_preflight.sh <fullerene-kernel-aarch64.Image>}
LOG=$(mktemp /tmp/ane_qemu.XXXXXX.log)

if ! command -v qemu-system-aarch64 >/dev/null; then
  echo "no qemu-system-aarch64 on this host"
  exit 2
fi

timeout 12 qemu-system-aarch64 -M virt -cpu cortex-a53 -m 2G \
  -display none -serial none -monitor none \
  -kernel "$IMG" \
  -d unimp,guest_errors,int -D "$LOG" >/dev/null 2>&1 || true

FIRST=$(grep -m1 -oE "addr 0x[0-9A-Fa-f]+, size [0-9]+, region" "$LOG" | grep -oE "0x[0-9A-Fa-f]+" | head -1)
echo "image    : $IMG"
echo "first rejected device access: ${FIRST:-none}"
echo

if [ -z "$FIRST" ]; then
  echo "FAIL: no rejected device access logged; the image did not reach the UART init"
  echo "(log: $LOG)"
  exit 1
fi

python3 - "$FIRST" <<'PY'
import sys
addr = int(sys.argv[1], 16)
if addr == 0xfff35020:
    print(f"PASS: first device access is the console clock gate {addr:#x} (CRG+0x20) -")
    print("      the black-box mark and everything before the first device touch ran;")
    print("      the next step is the PL011 init that QEMU lacks.")
    sys.exit(0)
base = 0xfdf02000
if base <= addr < base + 0x40:
    print(f"PASS: first device access is the PL011 block {addr:#x} - the black-box mark and")
    print("      everything before it ran; the next step is the UART init that QEMU lacks.")
    print("      (pre-2026-10-03 behaviour: builds that open the console clock gate first")
    print("      land at 0xfff35020 instead.)")
    sys.exit(0)
print(f"UNEXPECTED: first device access {addr:#x} is neither the console clock gate")
print(f"            0xfff35020 nor the PL011 block at {base:#x}")
sys.exit(1)
PY
RC=$?

echo
echo "== first exceptions"
grep -m3 -A4 "Taking exception" "$LOG" | head -16
echo
echo "(full log: $LOG)"
exit $RC
