#!/bin/bash
# Audit every ANE probe .S: a base address loaded as movz #((BASE)>>16), lsl #16
# MUST be followed by a movk of the low half when BASE's low 16 bits are nonzero.
# (The RCH probe shipped without those movk lines for VG1/G0; QEMU's defsyms were
# 64 KiB-aligned so the proof never saw it.)
cd /home/placeless/dev/p20-root || exit 1
fail=0
for f in ane_*.S; do
  python3 - "$f" <<'PY'
import re, sys, pathlib
path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
issues = []
for i, line in enumerate(lines):
    m = re.search(r'movz\s+([wx]\d+),\s*#\(\((\w+)\)\s*>>\s*16\)', line)
    if not m:
        continue
    reg, sym = m.group(1), m.group(2)
    win = lines[i+1:i+4]
    has_movk = any(re.search(rf'movk\s+{reg},\s*#\(\({sym}\)\s*&\s*0xffff\)', w) for w in win)
    if not has_movk:
        issues.append((i+1, line.strip()))
if issues:
    print(f"{path.name}:")
    for n, text in issues:
        print(f"  line {n}: {text}")
    sys.exit(1)
PY
  if [ $? -ne 0 ]; then fail=1; fi
done
[ $fail -eq 0 ] && echo "ALL CLEAN: every multi-part base load has its movk"
exit $fail
