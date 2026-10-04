#!/usr/bin/env python3
"""Verify the ANE early-vector park code (the eRecovery kill) in a built image.

The kill works by taking park-only exception vectors before the first device
access: any fault in the pre-`exceptions::install()` window must end in a WFE
park (which the loader answers with its fastboot window) instead of reaching
the loader's own handlers (which end in the rescue system).

The build strips the ELF's symbol table, so this verifier works on the raw
`.Image` (what gets embedded and flashed) with no symbols at all:

  1. Byte-scan for a 16-slot vector table: 16 branch instructions at a
     128-byte stride, zero padding between, every slot branching to one
     common handler. The table offset must be 2048-byte aligned (VBAR
     requires it; the Image maps offset = VA - 0x480000 and that base is
     page-aligned).
  2. Raw-disassemble the handler window: `msr daifset` first, the movz/movk
     pair building the step-mark address 0x348df000 (objdump prints the movz
     as the `mov` alias), the strb fault-byte store, and the wfe park loop.
  3. Find the installer by disassembling the whole image and looking for the
     `msr vbar_el1` whose window also contains `vbar_el2` and `CurrentEL`
     (the kernel's own vector install in exceptions.rs has neither), then
     check its address setup (a folded `adr`, or `adrp`+`add`) resolves to
     the byte-scanned table offset.

Usage: verify_ane_early_vectors.py <fullerene-kernel-aarch64.Image>
"""
import pathlib
import re
import struct
import subprocess
import sys

OBJDUMP = "aarch64-linux-gnu-objdump"


def disassemble(image: pathlib.Path, start: int | None = None,
                stop: int | None = None) -> str:
    command = [OBJDUMP, "-D", "-b", "binary", "-m", "aarch64"]
    if start is not None:
        command += [f"--start-address={start}", f"--stop-address={stop}"]
    command.append(str(image))
    return subprocess.check_output(command, text=True)


def find_vector_tables(data: bytes) -> list[tuple[int, int]]:
    """Return [(table_offset, handler_offset)] for 16-slot `b` tables."""
    found = []
    for offset in range(0, len(data) - 2048, 4):
        words = [struct.unpack_from("<I", data, offset + 128 * k)[0]
                 for k in range(16)]
        if not all(word >> 26 == 0x5 for word in words):  # B only
            continue
        if any(data[offset + 128 * k + 4: offset + 128 * (k + 1)] != bytes(124)
               for k in range(16)):
            continue
        targets = set()
        for k, word in enumerate(words):
            imm = word & 0x3FFFFFF
            if imm & 0x2000000:
                imm -= 0x4000000
            targets.add(offset + 128 * k + (imm << 2))
        if len(targets) == 1:
            found.append((offset, targets.pop()))
    return found


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    image = pathlib.Path(sys.argv[1])
    if not image.exists():
        print(f"FAIL: {image} does not exist")
        return 1
    data = image.read_bytes()
    print(f"image: {image} ({len(data):,} bytes)")

    tables = find_vector_tables(data)
    if not tables:
        print("FAIL: no 16-slot branch table found (early vectors missing)")
        return 1
    problems = []
    qualified = []
    for table_off, handler_off in tables:
        if table_off % 2048 != 0:
            problems.append(f"table at {table_off:#x}: not 2KB aligned")
            continue
        if not 0 <= handler_off <= len(data) - 64:
            continue
        window = disassemble(image, handler_off, handler_off + 64).lower()
        # objdump prints the movz as the `mov` alias; match the operands.
        needed = ("daifset", "#0xf000", "movk", "#0x348d", "strb", "wfe")
        if all(item in window for item in needed):
            qualified.append((table_off, handler_off, window))
    if not qualified:
        for problem in problems:
            print(f"FAIL: {problem}")
        print(f"FAIL: {len(tables)} candidate table(s), none disassemble as the "
              "park handler (msr daifset / 0xf000 + 0x348d build / strb / wfe)")
        return 1
    if len(qualified) > 1:
        print(f"FAIL: {len(qualified)} tables qualify; expected exactly one")
        return 1

    table_off, handler_off, window = qualified[0]
    print(f"vector table at {table_off:#x} (2KB aligned), handler at {handler_off:#x}")
    for line in window.splitlines():
        if line.strip():
            print("  " + line.strip())

    # 3. the installer: a vbar_el1 write whose window also has vbar_el2 and
    # CurrentEL - that combination exists only in ane_install_early_vectors.
    full = disassemble(image).splitlines()
    matched = None
    for index, line in enumerate(full):
        if "vbar_el1" in line and "msr" in line:
            window_lines = full[max(0, index - 10):index + 10]
            text = "\n".join(window_lines).lower()
            if "vbar_el2" in text and "currentel" in text:
                matched = (index, window_lines)
                break
    if matched is None:
        print("FAIL: no installer (msr vbar_el1 + vbar_el2 + CurrentEL) found")
        return 1

    index, window_lines = matched
    target = None
    for line in window_lines:
        low = line.lower()
        folded = re.search(r"\badr\s+x9,\s*(0x[0-9a-f]+)", low)
        if folded:
            # the assembler folds adrp+add into a single adr when the table
            # sits within its +-1MB range; the emitted form is what matters.
            target = int(folded.group(1), 16)
            break
        page = re.search(r"\badrp\s+x9,\s*(0x[0-9a-f]+)", low)
        if page:
            target = int(page.group(1), 16)
            continue
        if target is not None:
            low12 = re.search(r"\badd\s+x9, x9, #(0x[0-9a-f]+)", low)
            if low12:
                target += int(low12.group(1), 16)
                break
    print("installer window:")
    for line in window_lines:
        if line.strip():
            print("  " + line.strip())
    if target is None:
        print("FAIL: could not resolve the installer's address setup")
        return 1
    if target != table_off:
        print(f"FAIL: installer points at {target:#x}, table is at {table_off:#x}")
        return 1
    print(f"installer address setup resolves to the table ({target:#x})")

    print("PASS: early-vector park code verified in the Image "
          "(table -> hang handler -> step-mark store + WFE park; installer "
          "writes VBAR_EL1/EL2 and is addressed to the table)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
