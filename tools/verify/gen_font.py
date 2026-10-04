import pathlib
import re

# Parse the public-domain VGA 8x8 font (font8x8_basic.h, Marcel Sondaar/IBM).
hdr = pathlib.Path("/tmp/font8x8_basic.h").read_text()
rows = re.findall(r"\{\s*((?:0x[0-9A-Fa-f]{2},\s*)+0x[0-9A-Fa-f]{2})\},\s*// U\+([0-9A-Fa-f]{4})", hdr)
glyphs = {}
for bytes_s, cp in rows:
    vals = [int(v, 16) for v in re.findall(r"0x([0-9A-Fa-f]{2})", bytes_s)]
    assert len(vals) == 8, (cp, vals)
    glyphs[int(cp, 16)] = vals
assert all(c in glyphs for c in range(0x20, 0x60)), "missing printable glyphs"

# Emit the .S FONT table for 0x20..0x5F (space, punct, digits, :;<=>?@, A-Z, [\]^_)
# NB: font8x8_basic stores each row with the LSB as the leftmost pixel; the
# probe scans rows MSB-first. Bit-reverse every row so glyphs draw unmirrored.
lines = ["FONT:"]
for c in range(0x20, 0x60):
    b = [int(f"{x:08b}"[::-1], 2) for x in glyphs[c]]
    body = ",".join(f"0x{x:02X}" for x in b)
    lines.append(f"    .byte {body}   /* 0x{c:02X} '{chr(c)}' */")
table = "\n".join(lines) + "\n"

p = pathlib.Path("/home/placeless/dev/p20-root/ane_log_probe.S")
s = p.read_text()

# Replace the old 19-glyph FONT block (from 'FONT:' up to the blank line before _end).
i = s.find("FONT:")
j = s.find("\n\n_end:")
assert i != -1 and j != -1 and j > i
s = s[:i] + table + s[j:]

p.write_text(s)
print("FONT table: 64 glyphs (0x20..0x5F) written; map reduced to a 0x20..0x5F range check")
print("sample 'A':", " ".join(f"{x:02X}" for x in glyphs[0x41]))
print("sample ':' :", " ".join(f"{x:02X}" for x in glyphs[0x3A]))
print("sample ' ' :", " ".join(f"{x:02X}" for x in glyphs[0x20]))
