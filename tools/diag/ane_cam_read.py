#!/usr/bin/env python3
"""Read the ANE-LX2J's screen through the webcam and report saturated colours.

Measured 2026-10-02: the camera's auto-exposure hunts on the dim scene, so a
single frame is often near black - capture a small burst and keep the
brightest. Colours are reported in the RCH probe's legend (green / blue / red /
cyan / magenta fallback), which is what the framebuffer discovery reads out.

No dependencies beyond ffmpeg and the stdlib: frames come back as raw RGB24.

Usage: ane_cam_read.py [--frames 5] [--save DIR]
"""
import colorsys
import pathlib
import subprocess
import sys
import tempfile
import time

W, H = 640, 480


def capture(path, frames):
    best = None
    for _ in range(frames):
        try:
            subprocess.run(
                ["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "v4l2",
                 "-video_size", f"{W}x{H}", "-i", "/dev/video0",
                 "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24",
                 "-y", str(path)],
                timeout=25, check=False)
        except subprocess.TimeoutExpired:
            continue
        if not path.exists():
            continue
        data = path.read_bytes()
        if len(data) < W * H * 3:
            continue
        sample = data[::997]
        lum = sum(sample) / max(1, len(sample))
        if best is None or lum > best[0]:
            best = (lum, data)
    return best


def analyse(data):
    buckets = {k: 0 for k in ("red", "orange", "yellow", "green",
                              "cyan", "blue", "magenta")}
    saturated = 0
    for i in range(0, len(data) - 3, 21):
        r, g, b = data[i], data[i + 1], data[i + 2]
        mx, mn = max(r, g, b), min(r, g, b)
        # RCH fills are synthetic: fully saturated. A wooden desk or a warm
        # lamp sits far below this, so the threshold is deliberately strict.
        if mx < 100 or (mx - mn) < 140:    # dark or grey/warm-surface
            continue
        hd = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[0] * 360
        if hd < 15 or hd >= 345:   buckets["red"] += 1
        elif hd < 45:              buckets["orange"] += 1
        elif hd < 70:              buckets["yellow"] += 1
        elif hd < 165:             buckets["green"] += 1
        elif hd < 200:             buckets["cyan"] += 1
        elif hd < 280:             buckets["blue"] += 1
        else:                      buckets["magenta"] += 1
        saturated += 1
    return buckets, saturated


def main():
    frames, save = 5, None
    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a == "--frames" and i + 1 < len(args):
            frames = int(args[i + 1])
        if a == "--save" and i + 1 < len(args):
            save = args[i + 1]

    with tempfile.TemporaryDirectory() as td:
        raw = pathlib.Path(td) / "frame.rgb"
        best = capture(raw, frames)
    if not best:
        print("no frame captured")
        return 1
    lum, data = best
    print(f"frame luminance (sampled): {lum:.1f}")
    buckets, saturated = analyse(data)
    print(f"saturated pixels sampled: {saturated}")
    for k, v in sorted(buckets.items(), key=lambda kv: -kv[1]):
        if v:
            print(f"  {k:8s} {v}")
    top = max(buckets, key=buckets.get)
    if buckets[top]:
        print(f"dominant saturated colour: {top} ({buckets[top]} samples)")
    else:
        print("no saturated colour: screen dark or grey")
    if save:
        pathlib.Path(save).mkdir(parents=True, exist_ok=True)
        p = pathlib.Path(save) / f"cam_{time.strftime('%H%M%S')}.rgb"
        p.write_bytes(data)
        print(f"saved raw frame: {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
