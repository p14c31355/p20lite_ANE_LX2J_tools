#!/usr/bin/env python3
"""Host-side USB monitor for the ANE-LX2J (the re-enumeration harness).

Bramble lesson: when the target has no console, the reader lives on the HOST.
This is that reader for the ANE. It watches the phone's USB presence and
classifies every state it can be in, so a run is judged from machine-readable
output instead of a human squinting at the screen.

Sources (all free, no device cooperation needed):
  * lsusb polling      -> present/absent + vid:pid + product
  * /var/log/kern.log  -> the kernel's own enumeration story: descriptor reads,
                          address assignments, resets, and the -71-family errors
                          that a half-alive device (PHY up, no descriptors) shows
  * interface count    -> the fingerprints measured on this handset:
                          2 interfaces = early-boot/hung android
                          6 interfaces = healthy android
                          1 + File-CD Gadget = eRecovery fallback

State classification (the measured fingerprints):
  fastboot     18d1:d00d  (or a Huawei fastboot id)
  android      12d1:107e, Product ANE-LX2J, 6 interfaces, adb answers
  android-early 12d1:107e, 2 interfaces, no adb  = system up but not finished
  erecovery    12d1:107e + "Linux File-CD Gadget" on the bus
  dark         nothing on the bus
  unknown      any OTHER vid:pid -> this is the win signal: our own device

Output: a timeline TSV plus a one-line verdict at exit. Every run prints it.

Usage:
  ane_usb_monitor.py [--seconds N] [--follow] [--out FILE] [--quiet]
    --seconds N   watch for N seconds then print the verdict (default 90)
    --follow      keep watching until Ctrl-C (run it in the background while
                  you flash/reboot the phone)
    --out FILE    timeline path (default: usb_runs/ane_usb_<timestamp>.tsv)
"""

import argparse
import datetime as dt
import pathlib
import re
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent

# Measured fingerprints of this handset (2026-10-02, from kern.log):
#   fastboot  = 18d1:d00d, Product "Fastboot2.0"
#   android   = 12d1:107e, bcdDevice 2.99 (early/booting/healthy/erecovery all use it)
KNOWN_IDS = {
    "12d1:107e": "huawei-gadget",
    "18d1:d00d": "fastboot",
}

INTERFACE_ANDROID = 6
INTERFACE_EARLY = 2

# kern.log lines that matter for bring-up: they mean the DEVICE side spoke.
LOG_PATTERNS = [
    (re.compile(r"usb 1-1: new (high|full|super)-speed USB device"), "attach"),
    (re.compile(r"usb 1-1: New USB device found, idVendor=(\w+), idProduct=(\w+)"), "idd"),
    (re.compile(r"usb 1-1: Product: (.+)$"), "product"),
    (re.compile(r"usb 1-1: USB disconnect"), "disconnect"),
    (re.compile(r"usb 1-1: device descriptor read/64, error (-?\d+)"), "descr-err"),
    (re.compile(r"usb 1-1: device not accepting address (\d+), error (-?\d+)"), "addr-err"),
    (re.compile(r"usb 1-1: reset (high|full|super)-speed USB device"), "reset"),
    (re.compile(r"usb 1-1: unable to enumerate USB device"), "enum-fail"),
    (re.compile(r"usb 1-1: (device|USB device) not (accepting|responding)"), "no-response"),
]


def now() -> str:
    return dt.datetime.now().strftime("%H:%M:%S.%f")[:-3]


def lsusb_of_interest() -> dict:
    """Return {vid:pid: {'product': str, 'interfaces': n}} for 12d1/18d1."""
    out = {}
    try:
        res = subprocess.run(["lsusb"], capture_output=True, text=True, timeout=5)
    except Exception:
        return out
    for line in res.stdout.splitlines():
        m = re.search(r"ID ([0-9a-f]{4}:[0-9a-f]{4}) (.+)$", line)
        if not m:
            continue
        vid_pid, name = m.group(1), m.group(2).strip()
        if not vid_pid.startswith(("12d1", "18d1")):
            continue
        entry = {"product": name, "interfaces": -1}
        try:
            v = subprocess.run(["lsusb", "-v", "-d", vid_pid],
                               capture_output=True, text=True, timeout=5)
            entry["interfaces"] = v.stdout.count("bInterfaceNumber")
            pm = re.search(r"iProduct\s+\d+\s+(.+)$", v.stdout, re.M)
            if pm:
                entry["product"] = pm.group(1).strip()
        except Exception:
            pass
        out[vid_pid] = entry
    return out


def classify(present: dict, adb_ok: bool, cdrom: bool) -> str:
    if not present:
        return "dark"
    for vid_pid, info in present.items():
        if vid_pid == "18d1:d00d":
            return f"fastboot({vid_pid})"
        if vid_pid == "12d1:107e":
            if cdrom:
                return "erecovery"
            if info["interfaces"] >= INTERFACE_ANDROID or adb_ok:
                return "android"
            if info["interfaces"] in (INTERFACE_EARLY, 3, 4, 5):
                return f"android-booting({info['interfaces']}if)"
            return f"huawei-gadget({info['interfaces']}if)"
        if vid_pid not in KNOWN_IDS:
            return f"UNKNOWN-CANDIDATE({vid_pid})"
    return "huawei-other"


def adb_is_up() -> bool:
    try:
        r = subprocess.run(["adb", "devices"], capture_output=True, text=True, timeout=5)
        return bool(re.search(r"^\S+\tdevice$", r.stdout, re.M))
    except Exception:
        return False


def cdrom_on_bus() -> bool:
    try:
        r = subprocess.run(["lsusb", "-v", "-d", "12d1:107e"],
                           capture_output=True, text=True, timeout=5)
        return "File-CD Gadget" in r.stdout
    except Exception:
        return False


def kern_tail() -> list:
    """Last kern.log lines mentioning usb 1-1 (falls back to dmesg)."""
    for cmd in (["tail", "-n", "400", "/var/log/kern.log"],
                ["dmesg", "--ctime"]):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        except Exception:
            continue
        if r.returncode == 0 and r.stdout:
            lines = [l for l in r.stdout.splitlines() if "usb 1-1" in l]
            return lines[-25:]
    return []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=int, default=90)
    ap.add_argument("--follow", action="store_true")
    ap.add_argument("--out", default=None)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_path = pathlib.Path(args.out) if args.out else (
        HERE / "usb_runs" / f"ane_usb_{stamp}.tsv")
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # Seed the kern.log position so we only report NEW lines
    seen = set(kern_tail())

    t0 = time.time()
    last_state = None
    transitions = []
    counts = {}
    f = out_path.open("w")
    f.write("time\tstate\tvid_pid\tproduct\tinterfaces\tlog_event\n")

    deadline = None if args.follow else t0 + args.seconds
    exits = 0
    try:
        while True:
            if deadline and time.time() >= deadline:
                break
            present = lsusb_of_interest()
            adb_ok = False
            cdrom = False
            if present:
                cdrom = cdrom_on_bus()
                if "12d1:107e" in present:
                    adb_ok = adb_is_up()
            state = classify(present, adb_ok, cdrom)

            # new kern.log lines since last tick
            new_lines = [l for l in kern_tail() if l not in seen]
            for l in new_lines:
                seen.add(l)
                for pat, tag in LOG_PATTERNS:
                    m = pat.search(l)
                    if m:
                        f.write(f"{now()}\t{state}\t-\t-\t-\t{tag}: {l.strip()[:150]}\n")
                        if not args.quiet:
                            print(f"  [{now()}] {tag}: {l.strip()[:110]}")
                        break

            if state != last_state:
                first = next(iter(present)) if present else "-"
                info = present.get(first, {})
                f.write(f"{now()}\t{state}\t{first}\t"
                        f"{info.get('product','')}\t{info.get('interfaces','')}\t-\n")
                transitions.append((time.time() - t0, state))
                counts[state] = counts.get(state, 0) + 1
                if not args.quiet:
                    print(f"  [{now()}] => {state}  ({info.get('product','')}"
                          f"{', %s interfaces' % info['interfaces'] if info else ''})")
                last_state = state
            f.flush()
            time.sleep(0.5)
    except KeyboardInterrupt:
        exits = 1
    finally:
        f.close()

    # Verdict
    dur = time.time() - t0
    print(f"\n== verdict ({dur:.0f}s, timeline: {out_path})")
    print(f"  states seen: {', '.join(f'{s} x{n}' for s, n in counts.items())}")
    dark_total = sum(d for (d, s), _ in zip(transitions, transitions[1:])
                     if s == "dark") if len(transitions) > 1 else 0
    if dark_total:
        print(f"  dark span: {dark_total:.1f}s")
    win = [s for s in counts if s.startswith("UNKNOWN-CANDIDATE")]
    if win:
        print(f"  WIN SIGNAL: {win[0]} - a device id that is not the stock set")
    elif counts.get("dark") and len(transitions) >= 1:
        print("  (all-dark run: the device never came back to the bus)")
    return 0 if not win else 0


if __name__ == "__main__":
    sys.exit(main())
