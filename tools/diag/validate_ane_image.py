#!/usr/bin/env python3
"""Mechanical verification of an ANE-LX2J Fullerene image, no device needed.

Checks the three layers against each other:
  1. the ELF: the entry symbol sits at the address the loader will jump to
     (0x00480000 + the 64-byte Image header), and the BSS it zeroes stays
     inside RAM,
  2. the raw arm64 Image: header magic, entry branch, sizes,
  3. the packaged boot image: the ANE's own Android v0 header fields and a
     payload that gunzips back to exactly the Image.

Every check states the expected value and where it comes from.
"""
import gzip
import struct
import subprocess
import sys
from pathlib import Path

LINK_ENTRY = 0x00480040          # build.rs image_base for platform "ane"
KERNEL_ADDR = 0x00480000         # stock boot image header, kernel_addr
TAGS_ADDR = 0x07E00000           # stock boot image header, tags_addr
PAGE_SIZE = 2048                 # stock boot image header, page_size
PSTORE_BASE = 0x34800000         # ANE device tree: /reserved-memory/pstore-mem
PSTORE_END = PSTORE_BASE + 0x100000

fails = []
notes = []


def check(ok: bool, what: str, detail: str = "") -> None:
    tag = "ok  " if ok else "FAIL"
    print(f"  [{tag}] {what}{('  ' + detail) if detail else ''}")
    if not ok:
        fails.append(what)


def elf_sections(path: Path):
    """Minimal ELF64 reader: entry point and section table.

    The kernel ELF is stripped, so symbols are gone, but the entry point in the
    header and the section table survive - and those carry exactly what the
    loader contract is about.
    """
    d = path.read_bytes()
    assert d[:4] == b"\x7fELF" and d[4] == 2 and d[5] == 1, "not a little-endian ELF64"
    e_entry, = struct.unpack_from("<Q", d, 0x18)
    e_shoff, = struct.unpack_from("<Q", d, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", d, 0x3A)
    shs = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        nameoff, sh_type = struct.unpack_from("<II", d, off)
        sh_addr, sh_offset, sh_size = struct.unpack_from("<QQQ", d, off + 0x10)
        shs.append({"nameoff": nameoff, "type": sh_type, "addr": sh_addr,
                    "offset": sh_offset, "size": sh_size})
    strtab = shs[e_shstrndx]
    for sh in shs:
        end = d.index(b"\0", strtab["offset"] + sh["nameoff"])
        sh["name"] = d[strtab["offset"] + sh["nameoff"]:end].decode()
    return e_entry, shs


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: validate_ane_image.py <kernel-aarch64 ELF> <packaged .img> [Image]")
        return 2
    elf = Path(sys.argv[1])
    img = Path(sys.argv[2])
    image = Path(sys.argv[3]) if len(sys.argv) > 3 else None

    print("== 1. ELF entry and footprint")
    if elf.exists():
        entry, shs = elf_sections(elf)
        check(entry == LINK_ENTRY, "ELF entry point at the loader's jump address",
              f"e_entry={entry:#x} expected={LINK_ENTRY:#x}")
        bss = next((s for s in shs if s["name"] == ".bss"), None)
        if bss:
            end = bss["addr"] + bss["size"]
            print(f"       .bss {bss['addr']:#x}..{end:#x} ({bss['size']:#x} bytes)")
            check(end < PSTORE_BASE,
                  "zeroed BSS stays below the pstore window",
                  f"end={end:#x} pstore={PSTORE_BASE:#x}")
        else:
            check(False, ".bss section present")
        rela = next((s for s in shs if s["name"] == ".rela.dyn"), None)
        check(rela is not None, "static-PIE relocation table present",
              f".rela.dyn {rela['addr']:#x}+{rela['size']:#x}" if rela else "missing")
        names = {s["name"] for s in shs}
        check(".text.boot" in names, "entry shim section present (.text.boot)")
    else:
        check(False, "ELF exists", str(elf))

    print("== 2. raw arm64 Image")
    image_bytes = None
    if image and image.exists():
        image_bytes = image.read_bytes()
        check(image_bytes[0x38:0x3c] == b"ARM\x64", "arm64 magic at 0x38")
        code0, = struct.unpack_from("<I", image_bytes, 0)
        # b <offset> with offset = (0x14000000 | imm26), imm26 in instructions
        imm26 = code0 & 0x03FFFFFF
        target = 4 * imm26
        check(code0 >> 26 == 0x5 and target == 0x40,
              "entry stub branches over the 64-byte header", f"code0={code0:#010x} target=+{target:#x}")
        text_offset, image_size = struct.unpack_from("<QQ", image_bytes, 8)
        print(f"       text_offset={text_offset:#x} image_size={image_size:#x} file={len(image_bytes):,}")
    else:
        notes.append("no Image given; layer 2 skipped")

    print("== 3. packaged boot image")
    d = img.read_bytes()
    check(d[:8] == b"ANDROID!", "Android boot magic")
    ksize, kaddr = struct.unpack_from("<II", d, 8)
    rsize, raddr = struct.unpack_from("<II", d, 16)
    tags, = struct.unpack_from("<I", d, 32)
    page, = struct.unpack_from("<I", d, 36)
    check(kaddr == KERNEL_ADDR, "kernel_addr matches the stock header", f"{kaddr:#x}")
    check(tags == TAGS_ADDR, "tags_addr matches the stock header", f"{tags:#x}")
    check(page == PAGE_SIZE, "page_size matches the stock header", f"{page}")
    check(rsize == 0, "no ramdisk bundled (the ANE keeps it in its own partition)")
    head_end = PAGE_SIZE
    check(ksize <= len(d) - head_end, "payload fits in the file",
          f"kernel_size={ksize:,} file={len(d):,}")
    payload = d[head_end:head_end + ksize]
    gz_ok = payload[:2] == b"\x1f\x8b"
    check(gz_ok, "payload is a gzip stream", payload[:4].hex())
    if gz_ok:
        try:
            plain = gzip.decompress(payload)
            print(f"       gunzipped: {len(plain):,} bytes")
            if image_bytes is not None:
                check(plain == image_bytes, "gunzipped payload is byte-identical to the Image")
            check(plain[0x38:0x3c] == b"ARM\x64", "gunzipped payload carries the arm64 magic")
        except Exception as exc:  # noqa: BLE001 - diagnostic
            check(False, "payload gunzips", str(exc))
    cmd = d[0x40:0x240].split(b"\0")[0]
    print(f"       cmdline: {cmd[:70].decode('latin-1')}...")

    print()
    if notes:
        for n in notes:
            print(f"note: {n}")
    if fails:
        print(f"RESULT: {len(fails)} FAILED check(s)")
        return 1
    print("RESULT: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
