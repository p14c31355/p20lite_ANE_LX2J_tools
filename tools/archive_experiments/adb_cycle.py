#!/usr/bin/env python3
"""adb_cycle.py - one unmanned cycle step over the ANE's ADB wire.

Usage:
  adb_cycle.py log [outfile]   CNXN + OPEN(shell:log): collect the ring tail
  adb_cycle.py crash           CNXN + OPEN(shell:crash): deliberate panic ->
                               loader fastboot (the v63 chain), where the
                               armed engine flashes the next image.

The device answers roughly one conversation per boot window; run this in the
first ~40 s after the enumeration event (led by night_engine.sh). The CNXN is
sent twice because the first EP1 OUT of a session can lag one transfer.
"""
import struct
import sys
import time

import usb.core
import usb.util

CNXN = 0x4E584E43
OPEN = 0x4E45504F
OKAY = 0x59414B4F
WRTE = 0x45545257
CLSE = 0x45534C43


def frame(cmd, a0, a1, payload=b""):
    checksum = sum(payload) & 0xFFFFFFFF
    return (
        struct.pack("<IIIIII", cmd, a0, a1, len(payload), checksum, cmd ^ 0xFFFFFFFF)
        + payload
    )


def connect():
    # Fire the one clean conversation of this window the moment the device
    # appears: poll at 0.5 s so the shot lands right after the enumeration
    # completes, and keep the total wait modest (a device absent for ~15 s
    # usually means a stuck enumeration; the next boot is the better bet).
    for _ in range(30):
        dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
        if dev is not None:
            break
        time.sleep(0.5)
    if dev is None:
        return None
    try:
        dev.set_configuration()
    except Exception:
        pass
    return dev


def drain(dev):
    for _ in range(8):
        try:
            r = dev.read(0x81, 65536, timeout=200)
            if not r:
                break
        except usb.core.USBError:
            break


def read_frames(dev, seconds):
    buf = b""
    t0 = time.time()
    errs = {}
    while time.time() - t0 < seconds:
        try:
            data = bytes(dev.read(0x81, 65536, timeout=1000))
            if data:
                buf += data
        except usb.core.USBError as e:
            if e.errno == 110:
                if buf:
                    break
                continue
            # v176 forensics: surface non-timeout read errors (EIO etc.) -
            # they used to be swallowed silently, which made "raw: 0"
            # ambiguous between "no data" and "every read failed".
            errs[str(e)] = errs.get(str(e), 0) + 1
            time.sleep(0.2)
    if errs:
        print("read errors:", errs)
    return buf


def parse_frames(buf):
    """Tolerant frame scan.

    The first reply of a fresh boot can carry stale TX-FIFO bytes ahead of
    the real frames (the loader's leftovers), and a strict parse-at-offset-0
    turns that into "no reply". Slide forward until a valid frame header
    appears, then chain frames from there. Keep the raw bytes for forensics
    by writing them next to the output file in the caller.
    """
    out = []
    i = 0
    n = len(buf)
    while i + 24 <= n:
        cmd, a0, a1, ln, csum, magic = struct.unpack_from("<IIIIII", buf, i)
        if magic != (cmd ^ 0xFFFFFFFF) or ln > 65536:
            i += 1  # slide one byte and rescan
            continue
        payload = buf[i + 24 : i + 24 + ln]
        if len(payload) < ln:
            # v191: accept the truncated tail. The link often dies mid-reply
            # (the magic reset fires while the drain is still in flight), and
            # a partial piggyback is far better than none: the ring tail is
            # written even when only the first bytes arrived.
            out.append((cmd, a0, a1, payload))
            break
        out.append((cmd, a0, a1, payload))
        i += 24 + ln
    return out


def send_twice(dev, data):
    try:
        dev.write(0x01, data, timeout=5000)
        return True
    except Exception as e:
        print("write1:", e)
    time.sleep(0.3)
    try:
        dev.write(0x01, data, timeout=5000)
        return True
    except Exception as e:
        print("write2:", e)
    return False


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("log", "crash"):
        print(__doc__)
        sys.exit(2)
    mode = sys.argv[1]
    dev = connect()
    if dev is None:
        print("no device")
        sys.exit(2)
    # Re-arm EP1 like the fastboot tools: SET_CONFIGURATION(0) -> (1).
    # v307 caution: on a FRESH kernel enumeration the config is already 1;
    # a 0->1 dance shows the device a config-0 window and the v306 quiet
    # detector can read that as the host walking away (D+ cycle mid-window).
    # Only dance when the device reports NOT configured.
    cfg = None
    try:
        cfg = dev.get_configuration()
    except Exception:
        cfg = None
    already1 = getattr(cfg, 'bConfigurationValue', None) == 1
    if not already1:
        try:
            dev.ctrl_transfer(0, 9, 0, 0, None, timeout=3000)
            time.sleep(0.3)
            dev.ctrl_transfer(0, 9, 1, 0, None, timeout=3000)
            time.sleep(0.5)
        except Exception as e:
            # v176 forensics: this used to be `except Exception: pass`, which hid
            # whether the EP1 re-arm actually happened. If SET_CONFIGURATION
            # itself fails, EP1 was never re-armed and every later bulk read/write
            # runs against a stale/wedged endpoint.
            print("dance error:", e)
    else:
        print("config already 1; skipping the 0->1 dance")
    drain(dev)

    # v156 cycle magic: the log mode's CNXN carries arg0 0xC0DE0001. The
    # device replies with the ring piggyback and then panics itself into the
    # loader's fastboot, so one conversation both collects and resets.
    magic = 0xC0DE0001 if mode == "log" else 0x01000001
    send_twice(dev, frame(CNXN, magic, 4096, b"host::adbtest\x00"))
    raw = read_frames(dev, 20)
    # Forensics: keep the last raw reply so the residue bytes (stale TX-FIFO
    # prefix) and frame layout can be inspected after a failed parse.
    if raw:
        try:
            with open("/tmp/adb_raw_last.bin", "wb") as f:
                f.write(raw)
        except OSError:
            pass
    fr = parse_frames(raw)
    got_cnxn = any(f[0] == CNXN for f in fr)
    print("cnxn reply:", got_cnxn, "frames:", len(fr), "raw:", len(raw))
    if not got_cnxn:
        sys.exit(1)

    if mode == "log":
        out = sys.argv[2] if len(sys.argv) > 2 else "ring_adb.bin"
        # v155 piggyback: the CNXN reply's payload carries the banner plus the
        # durable ring tail, NUL-separated. The follow-up OPEN conversation is
        # unreliable on a stalled boot (that is why every pull came back 0
        # bytes), so prefer the piggyback and only fall back to OPEN(shell:log)
        # when the reply carries no ring.
        ring = b""
        for cmd, a0, a1, pl in fr:
            if cmd == CNXN and b"\x00" in pl:
                ring = pl.split(b"\x00", 1)[1]
                if ring:
                    break
        if ring:
            with open(out, "wb") as f:
                f.write(ring)
            print("ring bytes:", len(ring), "(piggyback) ->", out)
            return
        send_twice(dev, frame(OPEN, 1, 0, b"shell:log\x00"))
        fr2 = parse_frames(read_frames(dev, 25))
        run = b""
        for cmd, a0, a1, pl in fr2:
            if cmd == WRTE and len(pl) > 1:
                run += pl[1:]
        with open(out, "wb") as f:
            f.write(run)
        print("ring bytes:", len(run), "->", out)
    elif mode == "crash":
        send_twice(dev, frame(OPEN, 2, 0, b"shell:crash\x00"))
        print("crash sent")


if __name__ == "__main__":
    main()
