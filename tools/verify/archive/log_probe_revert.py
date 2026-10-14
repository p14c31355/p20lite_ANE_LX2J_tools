import pathlib
import re

p = pathlib.Path("/home/placeless/dev/p20-root/ane_log_probe.S")
s = p.read_text()

# 1) remove the USB section (from its comment to the RC comment)
i = s.find("    /* USB gadget fields:")
j = s.find('    /* record lines: "RC " + 24 hex chars')
assert i != -1 and j != -1 and j > i, (i, j)
s = s[:i] + s[j:]

# 2) remove the USB seeds (from the seed comment to .endif)
i = s.find("    /* USB field seeds")
j = s.find(".endif", i)
assert i != -1 and j != -1 and j > i, (i, j)
s = s[:i] + s[j:]

# 3) log tail back to 540
assert s.count("    mov  w25, #405") == 1
s = s.replace("    mov  w25, #405", "    mov  w25, #540")
assert s.count("    mov  w24, #405") == 1
s = s.replace("    mov  w24, #405", "    mov  w24, #540")
p.write_text(s)
print("revert: USB section + seeds removed; log tail back to 540")

q = pathlib.Path("/home/placeless/dev/p20-root/ane_log_probe.sh")
t = q.read_text()
old = '''tail = b"VBCDEFGHIJKL" + bytes(393)
usb = (b"USB CORE FF100000 AHBIF FF200000" + b" " * 13
       + b"ID=12345678 CFG=A1B2C3D4 CTL=0000F001" + b" " * 8
       + b"DST=00070001 AHB=00030001 BC=0000000C" + b" " * 8)'''
# the sh may still carry the *14 variant if sed ran on the older text; normalise both
old14 = old.replace('b" " * 13', 'b" " * 14')
if old14 in t:
    t = t.replace(old14, 'tail = b"VBCDEFGHIJKL" + bytes(528)')
elif old in t:
    t = t.replace(old, 'tail = b"VBCDEFGHIJKL" + bytes(528)')
else:
    raise SystemExit("expected-block not found in sh")
t = t.replace('s = (tail + usb).decode("latin-1")', 's = tail.decode("latin-1")')
q.write_text(t)
print("sh: expected reverted to 540-tail + RC")
