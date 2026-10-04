#!/usr/bin/env python3
# Poll the QEMU trace until it fills (the delay loops are long in TCG).
import json, select, struct, subprocess, sys, time, re

image = sys.argv[1]
expected = struct.pack("<22I",
    11, 0x1,
    1, 0x46, 2, 0x05000000, 3, 0x08004C00, 4, 0x14, 5, 0x06B866DB,
    6, 0x08006C00, 7, 0x08007C00, 8, 0x08007E00, 9, 0x0C, 10, 0x00)

proc = subprocess.Popen(
    ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a53", "-m", "2G",
     "-display", "none", "-serial", "none", "-qmp", "stdio",
     "-kernel", image],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

def qmp(obj, timeout=15):
    proc.stdin.write((json.dumps(obj) + "\n").encode())
    proc.stdin.flush()
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select([proc.stdout], [], [], max(0.1, deadline - time.time()))
        if not ready:
            continue
        line = proc.stdout.readline()
        if not line:
            return None
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "return" in msg or "error" in msg:
            return msg
    return None

def dump(addr, count):
    reply = qmp({"execute": "human-monitor-command",
                 "arguments": {"command-line": f"xp /{count}bx {addr}"}})
    text = (reply or {}).get("return", "")
    return bytes(int(t, 16) for t in re.findall(r"0x([0-9a-fA-F]{2})\b", text))

qmp({"execute": "qmp_capabilities"})
t0 = time.time()
got = b""
while time.time() - t0 < 300:
    time.sleep(5)
    got = dump(0x42001000, 88)
    done = sum(1 for i in range(0, 88, 8) if got[i:i+4] != b"\0\0\0\0")
    print(f"  t={time.time()-t0:5.1f}s  entries filled: {done}/11", flush=True)
    if got[:88] == expected[:88]:
        break
pmic = dump(0x42006100, 32)
sctrl = dump(0x4200743C, 8)
qmp({"execute": "quit"})
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()

ok_trace = got[:88] == expected[:88]
ok_pmic = len(pmic) >= 16 and pmic[15] == 0x01
ok_sctrl = len(sctrl) >= 4 and sctrl[0:4] == b"\x01\x00\x00\x00"
print(f"  trace got     : {got[:88].hex(' ')}")
print(f"  pmic  +0x10F  : {' '.join(f'{b:02x}' for b in pmic[14:18])}  (want .. 01 .. ..)")
print(f"  sctrl +0x43C  : {' '.join(f'{b:02x}' for b in sctrl[0:4])}  (want 01 00 00 00)")
print("  trace: " + ("PASS" if ok_trace else "FAIL") + "   abb writes: " + ("PASS" if (ok_pmic and ok_sctrl) else "FAIL"))
sys.exit(0 if (ok_trace and ok_pmic and ok_sctrl) else 1)
