#!/usr/bin/env python3
"""Package a Fullerene Image into the ANE's stock kernel image.

The LK on this handset rejects small hand-made payloads (rescue: INVALID BOOT
IMAGE HEADER) while accepting the stock-shaped 11.7 MB image. So Fullerene is
delivered the same way the working probe is: take the stock Image, and write
Fullerene's Image over the stock's own entry point.

    stock code0 (byte 0)      b +0x1660000
    our payload           ->  Fullerene Image (its own code0: b +0x40)
                              Fullerene _start (MMU-off preamble, ...)

Fullerene is static-PIE, so its linked base is irrelevant at runtime; the
payload only has to be reachable and entered. Everything else in the stock
image is left untouched so the LK's own checks see the stock.

Usage:
    mkane_stock_embed.py <fullerene.Image> [out.img]
"""
import gzip
import pathlib
import struct
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
STOCK_IMAGE = HERE / "firmware" / "ane_bootimg" / "stock_Image"
ENTRY_OFF = 0x1660000


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    src = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else \
        HERE / "artifacts" / "fullerene-ane-stock-embed.img"

    fullerene = src.read_bytes()
    stock = bytearray(STOCK_IMAGE.read_bytes())

    # sanity on our own image
    code0 = struct.unpack_from("<I", fullerene, 0)[0]
    if fullerene[0x38:0x3C] != b"ARMd" or code0 != 0x14000010:
        print(f"refusing: unexpected Fullerene Image header (code0={code0:#x})")
        return 1
    if ENTRY_OFF + len(fullerene) > len(stock):
        print("refusing: Fullerene does not fit at the entry offset")
        return 1

    stock[ENTRY_OFF:ENTRY_OFF + len(fullerene)] = fullerene
    tmp = HERE / "artifacts" / ".stock_embed_image.tmp"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_bytes(bytes(stock))

    subprocess.run(
        [sys.executable, str(HERE / "mkane_bootimg.py"), str(tmp), str(out), "--gzip"],
        check=True)

    # verify what we produced
    data = out.read_bytes()
    assert data[:8] == b"ANDROID!", "not an ANDROID! image"
    ks = struct.unpack_from("<I", data, 8)[0]
    ps = struct.unpack_from("<I", data, 36)[0]
    payload = gzip.decompress(data[ps:ps + ks])
    got = payload[ENTRY_OFF:ENTRY_OFF + len(fullerene)]
    print(f"outer: stock Image {len(stock):,} B, code0 untouched "
          f"({struct.unpack_from('<I', data, ps)[0] and ''}"
          f"{payload[:4].hex(' ')})")
    print(f"packaged: {out} ({len(data):,} B, kernel_size={ks:,})")
    print(f"fullerene image placed at {ENTRY_OFF:#x}: "
          f"{'byte-exact' if got == fullerene else 'MISMATCH'}")
    tmp.unlink(missing_ok=True)
    return 0 if got == fullerene else 1


if __name__ == "__main__":
    sys.exit(main())
