#!/usr/bin/env bash
# The cheap USB-mode test: can plain adb shell make the transfer mode
# persistent, without the exploit?
#
# The hand-work this targets: after a reboot the phone comes up in a mode
# where adb is off, so the user has to pick "ファイル転送" and accept the
# dialog again.  Everything about that is a property in userspace, and the
# property service persists any persist.* property it accepts.  So the
# question is only whether the adb shell user is allowed to set
# persist.sys.usb.config - one getprop pair answers the in-memory half, and
# the next natural boot after the setprop answers the persistence half.
#
# This deliberately does NOT reboot the phone: adb windows are scarce and a
# reboot spent here is a probe cycle lost.  The setprop lands, the result is
# recorded, and the runner's own reboots serve as the test cycles; the
# morning report (or any later getprop) reads the verdict.
set -u
cd "$(dirname "$0")"
LOG=usb_runs/usbcheap.log
VERDICT=usb_runs/usbcheap_verdict.txt
mkdir -p usb_runs

say() { echo "$(date '+%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }
adb_ok() { timeout 15 adb devices 2>/dev/null | grep -qw device; }

say "armed: waiting for an adb window (fast poll - the runner claims windows too; a 1s setprop rides along with its reboot)"
for i in $(seq 1 900); do
  adb_ok && break
  sleep 10
done
if ! adb_ok; then
  say "gave up: no adb window in ~2.5h"; echo "NO-WINDOW" > "$VERDICT"; exit 1
fi

before=$(timeout 20 adb shell 'getprop persist.sys.usb.config; getprop sys.usb.state; settings get global adb_enabled' 2>&1 | tr -d '\r')
say "before: $(echo "$before" | tr '\n' '|')"

setout=$(timeout 20 adb shell 'setprop persist.sys.usb.config mtp,adb && getprop persist.sys.usb.config' 2>&1 | tr -d '\r')
say "setprop result: $(echo "$setout" | tr '\n' '|')"
served=$(echo "$setout" | tail -1)
if [ "$served" != "mtp,adb" ]; then
  say "VERDICT: shell cannot set the property (value did not come back) - the exploit route stays the only one"
  echo "SETPROP-DENIED" > "$VERDICT"
  exit 1
fi

# The value came back from the property service: in-memory accepted.  Whether
# it PERSISTS shows on the next boot (persist.* is written out by the property
# service itself).  Record the evidence and stop; do not spend a reboot.
echo "SETPROP-ACCEPTED (persistence to prove on the next boot)" > "$VERDICT"
say "VERDICT: setprop accepted (mtp,adb) - persistence will show on the next adb window"
say "         (check with: adb shell getprop persist.sys.usb.config)"
exit 0
