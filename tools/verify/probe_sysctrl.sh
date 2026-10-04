#!/bin/bash
# Does the ANE tree carry a hisilicon,sysctrl node (the abb prepare needs it)?
cd /home/placeless/dev/p20-root || exit 1
echo "=== nodes whose compatible mentions sysctrl ==="
grep -i "sysctrl" firmware/ane_dtb/fdt_properties.txt | grep -i compatible | head -8
echo
echo "=== their reg values ==="
python3 - <<'PY'
import pathlib
lines = pathlib.Path("firmware/ane_dtb/fdt_properties.txt").read_text(errors="replace").splitlines()
for line in lines:
    parts = line.split("\t")
    if len(parts) < 3: continue
    node, prop, val = parts[0], parts[1], parts[2]
    if "sysctrl" in node.lower() and prop in ("compatible", "reg", "status"):
        try:
            s = bytes.fromhex(val).rstrip(b"\0").replace(b"\0", b" | ").decode(errors="replace")
            print(f"{node} :: {prop} = {s}")
        except Exception:
            print(f"{node} :: {prop} = {val}")
PY
