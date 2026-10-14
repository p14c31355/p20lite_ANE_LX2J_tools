#!/bin/bash
# Keep the ANE's screen awake and bright for camera observation.
#
# Measured 2026-10-02: the home screen dims and turns off with time, which is
# why early webcam frames were nearly black. Run this on every Android window;
# the periodic wake-up covers the screen timeout that adb settings alone did
# not beat (svc stayon is not enough when the port charges slowly).
set -u
cd "$(dirname "$0")"

if ! timeout 10 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$"; then
  echo "no adb device"; exit 1
fi

timeout 15 adb shell 'settings put system screen_off_timeout 2147483647
settings put system screen_brightness 255
settings put system screen_brightness_mode 0
svc power stayon true
input keyevent KEYCODE_WAKEUP
echo "screen: brightness=$(settings get system screen_brightness) timeout=$(settings get system screen_off_timeout)"' 2>&1 | tail -3

if [ "${1:-}" = "--watch" ]; then
  echo "periodic wake-up (every 120 s); Ctrl-C to stop"
  while true; do
    sleep 120
    timeout 10 adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  done
fi
