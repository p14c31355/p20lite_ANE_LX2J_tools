#!/usr/bin/env python3
"""
Enumerate the partition images inside UPDATE.APP, in write order.

If the FIRST image written is the bootloader (xloader / fastboot), then a stop at
a low percentage is consistent with the hardware refusing a lower-version
bootloader (anti-rollback), which no packaging change can bypass.

Huawei UPDATE.APP layout (see huawei-playground/update-extractor.py):
    4 bytes            magic
    <LLQLL 24 bytes    hdr_sz, unk1, hw_id, seq, size
    48 bytes           date[16], time[16], type[16]   <- type is the partition name
    ...                blank1[16], hdr_crc[2], block_size[2], blank2[2], checksum[...]
    size bytes         payload
    then aligned to ALIGNMENT
"""
import zipfile

Z = "/tmp/fw3/Software/dload/update_sd.zip"

with zipfile.ZipFile(Z) as z:
    with z.open("UPDATE.APP") as f:
        head = f.read(4 * 1024 * 1024)      # enough for the first several headers
        # we only need to walk headers, but must know where payloads are, so read
        # progressively from the stream instead
    with z.open("UPDATE.APP") as f:
        import struct
        pos = 0
        ALIGN = 4

        def read_at(offset, n):
            f.seek(offset)
            return f.read(n)

        seen = 0
        while seen < 40:
            magic = read_at(pos, 4)
            if len(magic) < 4:
                break
            hdr = read_at(pos + 4, 24)
            if len(hdr) < 24:
                break
            hdr_sz, unk1, hw_id, seq, size = struct.unpack("<LLQLL", hdr)
            meta = read_at(pos + 28, 48)
            if len(meta) < 48:
                break
            date = meta[0:16].decode("ascii", "replace").strip("\x00")
            time = meta[16:32].decode("ascii", "replace").strip("\x00")
            ptype = meta[32:48].decode("ascii", "replace").strip("\x00")
            if not ptype or hdr_sz > 4096 or size < 0 or size > 5_000_000_000:
                print(f"  [stop] implausible header at {pos:#x}: hdr_sz={hdr_sz} "
                      f"size={size} type={ptype!r}")
                break
            print(f"  [{seen:>2}] offset {pos:#012x}  type={ptype:<16} "
                  f"size={size:>12,}  date={date} {time}  hw_id={hw_id:#x} seq={seq}")
            seen += 1
            pos = pos + hdr_sz + size
            pos += (ALIGN - (pos % ALIGN)) % ALIGN
            if pos > 6_000_000_000:
                break
        print(f"\n  total images listed: {seen}")
