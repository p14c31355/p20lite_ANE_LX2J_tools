#!/usr/bin/env python3
"""v110 rescue v2: precise probe of the fresh-boot USB window.

The v110 kernel's USB answers only between enumeration (~17 s in) and the
launchd wedge (~35 s in). Probe every 2 s with a fast getvar; the moment one
answers, send reboot-bootloader so the loader sits in fastboot (reason =
BOOTLOADER), then flash v111."""
import subprocess
import time

SER = "SCV7N18927000473"
IMG = "artifacts/fullerene-ane-v111-launchd-stock.img"


def dev_state():
    out = subprocess.run(["lsusb", "-v", "-d", "18d1:d00d"], capture_output=True, text=True).stdout
    if "Fastboot2.0" in out:
        return "LK"
    if "ANE fastboot" in out:
        return "KERNEL"
    return "NONE"


def run(args, t=6):
    return subprocess.run(["timeout", str(t)] + args, capture_output=True, text=True).stdout


def flash_lk():
    print("LK SITTING - flashing v111", flush=True)
    print(run(["fastboot", "-s", SER, "flash", "kernel", IMG], 60), flush=True)
    print(run(["fastboot", "-s", SER, "reboot"], 10), flush=True)


prev = dev_state()
print("start:", prev, flush=True)
t0 = time.time()
while time.time() - t0 < 1200:
    s = dev_state()
    if s != prev:
        print(f"{time.time()-t0:7.1f}s {prev} -> {s}", flush=True)
        prev = s
        if s == "LK":
            flash_lk()
            break
        if s == "KERNEL":
            time.sleep(15)
            for k in range(10):
                out = run(["fastboot", "-s", SER, "getvar", "serialno"], 4)
                ok = "serialno" in out
                print(f"  probe {k}: ok={ok}", flush=True)
                if ok:
                    out2 = run(["fastboot", "-s", SER, "reboot-bootloader"], 6)
                    print(f"  reboot sent: {out2.strip()[:120]!r}", flush=True)
                    break
                time.sleep(2)
    time.sleep(0.3)
print("done", f"{time.time()-t0:.1f}s", flush=True)
