#!/usr/bin/env python3
"""
Verify BOTH views of the EOCD-confusion package independently.

  forward scan  (find the FIRST EOCD)   -> what the recovery's verifier parses
  backward scan (find the LAST EOCD)    -> what minzip parses

Note: python's zipfile walks backwards, so it can only ever show the second view.
The first view has to be parsed by hand.

This also fixes the bug in the earlier checker: a central directory entry's offset
points at the LOCAL HEADER, so the file data starts 30 + name_len + extra_len
bytes later.
"""
import struct
import zlib

P = "/home/placeless/dev/p20-root/firmware/eocd/update_sd.zip"
ORIG = "/tmp/fw3/Software/dload/update_sd.zip"
EOCD_SIG = b"PK\x05\x06"
CEN_FMT = "<IHHHHHHIIIHHHHHII"
EOCD_FMT = "<IHHHHIIH"

data = open(P, "rb").read()
orig = open(ORIG, "rb").read()
print(f"patched {len(data):,} bytes   original {len(orig):,} bytes   delta {len(data)-len(orig):+,}")


def local_data(buf, off, method, csize):
    n, e = struct.unpack("<HH", buf[off + 26:off + 30])
    raw = buf[off + 30 + n + e: off + 30 + n + e + csize]
    return zlib.decompress(raw, -15) if method == 8 else raw


def walk(buf, eocd_pos, label):
    s = struct.unpack(EOCD_FMT, buf[eocd_pos:eocd_pos + 22])
    n_total, cd_size, cd_off = s[4], s[5], s[6]
    print(f"\n=== {label}: EOCD @{eocd_pos:#x}  entries={n_total} cd_off={cd_off:#x} cd_size={cd_size}")
    cd = buf[cd_off:cd_off + cd_size]
    q = 0
    while q < len(cd):
        f = struct.unpack(CEN_FMT, cd[q:q + 46])
        nlen, elen, clen = f[10], f[11], f[12]
        name = cd[q + 46:q + 46 + nlen]
        method, csize, usize, doff = f[4], f[8], f[9], f[16]
        if name == b"SOFTWARE_VER_LIST.mbn":
            body = local_data(buf, doff, method, csize)
            print(f"   {name.decode():46} off={doff:#x} -> {body!r}")
        else:
            print(f"   {name.decode():46} off={doff:#x}")
        q += 46 + nlen + elen + clen


first = data.find(EOCD_SIG)
last = data.rfind(EOCD_SIG)
print(f"first EOCD @{first:#x}   last EOCD @{last:#x}   (differ: {first != last})")
walk(data, first, "forward scan - the verifier's view")
walk(data, last, "backward scan - minzip's view")

# byte-for-byte: the region before the first EOCD must be untouched
print("\n=== is everything before the first EOCD identical to the original?")
print("   ", data[:first] == orig[:first])

# and the original comment (the signature) must be intact within the new comment
print("=== is the original signature comment intact?")
s = struct.unpack(EOCD_FMT, data[first:first + 22])
new_comment = data[first + 22: first + 22 + s[7]]
old_comment_len = struct.unpack(EOCD_FMT, orig[first:first + 22])[7]
old_comment = orig[first + 22: first + 22 + old_comment_len]
print("   original comment preserved as a prefix:", new_comment[:old_comment_len] == old_comment)
print("   new comment length:", s[7], "(was", old_comment_len, ")")
