#!/usr/bin/env python3
"""v110 hunter v3: probe the very first seconds after each fresh kernel
attach (the untested zone) and reboot into the loader the moment one answers.

The kernel's service() runs in bursts during platform init, so a client
session may wait seconds for its dispatch: give each attempt a 9 s client
timeout and try twice per boot (+3 s and +12 s)."""
import subprocess
import time

SER = "SCV7N18927000473"


def state():
    out = subprocess.run(["lsusb", "-v", "-d", "18d1:d00d"], capture_output=True, text=True).stdout
    return "LK" if "Fastboot2.0" in out else ("KERNEL" if "ANE fastboot" in out else "NONE")


def run(a, t):
    return subprocess.run(["timeout", str(t)] + a, capture_output=True, text=True).stdout


prev = state()
t0 = time.time()
print("hunter start:", prev, flush=True)
while time.time() - t0 < 1500:
    s = state()
    if s != prev:
        prev = s
        print(f"{time.time()-t0:6.1f}s -> {s}", flush=True)
        if s == "KERNEL":
            time.sleep(3)
            for k in range(2):
                out = run(["fastboot", "-s", SER, "getvar", "serialno"], 9)
                ok = ("serialno" in out) or ("OKAY" in out)
                print(f"{time.time()-t0:6.1f}s probe{k} ok={ok} {out.strip()[:60]!r}", flush=True)
                if ok:
                    print("  CONNECTED - reboot-bootloader", flush=True)
                    print("  " + run(["fastboot", "-s", SER, "reboot-bootloader"], 6).strip(), flush=True)
                    break
                time.sleep(1)
        time.sleep(0.2)
print("hunter done", flush=True)
