#!/bin/bash
# Make MTP + adb the default USB mode on the ANE-LX2J.
#
# Why: the persistent config reads
#   persist.sys.usb.config = hisuite,mtp,mass_storage,adb
# with Huawei's HiSuite mode first - which is why the phone keeps asking and the
# user has to pick "file transfer" by hand each time. Setting just "mtp,adb"
# makes both the file transfer and adb come up straight away, with no
# interaction - which also removes the button dance from our experiments
# (adb reboot bootloader works from a booted system).
#
# Operational recipe copied from nvme_session.sh, the clean-boot session that
# actually won on 2026-10-02: the exploit needs a freshly booted, SETTLED
# system and one run per boot (later runs on the same boot die silently).
# The first version of this script ran ~8 seconds after the boot window
# appeared and believed whatever /data/local/tmp/cve-2019-2215 was already
# there - both are exactly the states the exploit fails in ("no root shell").
# So now: always verify the frozen winning build (delta 0x134c838, see
# working/README.txt) by md5, reboot, wait for boot_completed, settle 75s,
# then start the root shell with a fifo kept open and drive it with markers.
set -u
cd "$(dirname "$0")"

EXP=/data/local/tmp/cve-2019-2215
FROZEN="$HOME/dev/p20-root/working/cve-2019-2215_0x134c838"
WANT_MD5=$(md5sum "$FROZEN" | cut -d' ' -f1)

if ! timeout 15 adb devices 2>/dev/null | awk 'NR==2{print $2}' | grep -q device; then
  echo "device is not on adb"; exit 1
fi

echo "== before"
timeout 10 adb shell getprop persist.sys.usb.config

echo "== ensure the frozen exploit is on the device"
GOT_MD5=$(timeout 30 adb shell "md5sum $EXP 2>/dev/null" | awk '{print $1}')
if [ "$GOT_MD5" != "$WANT_MD5" ]; then
  echo "  device has '${GOT_MD5:-nothing}'; pushing the frozen build"
  timeout 60 adb push "$FROZEN" "$EXP" 2>&1 | tail -1
  timeout 10 adb shell "chmod 755 $EXP"
  GOT_MD5=$(timeout 30 adb shell "md5sum $EXP" | awk '{print $1}')
fi
if [ "$GOT_MD5" != "$WANT_MD5" ]; then
  echo "  FATAL: wrong binary on the device ($GOT_MD5)"; exit 1
fi
echo "  md5 ok ($GOT_MD5)"

echo "== reboot for a clean heap and let the system settle (the winning recipe)"
UP=$(timeout 10 adb shell 'cat /proc/uptime' 2>/dev/null | awk '{print int($1)}')
if [ "${UP:-9999}" -lt 150 ]; then
  echo "  system is ${UP}s old - fresh enough, skipping the reboot"
else
  echo "  system is ${UP}s old - rebooting for a clean heap"
  timeout 60 adb reboot
  # The boot_completed check can read the OLD boot's value for a few seconds
  # after the reboot command returns (measured: the first check right after
  # adb reboot still answered 1, which ate the settle time). Wait for the old
  # boot to actually go down first.
  sleep 40
fi
# A failed exploit run makes the NEXT boot slow (measured: ~7-10 minutes to a
# reachable adb), so wait patiently for a settled boot - and bail out if it
# never comes. A 600s root poll against a dead adb is pure waste.
echo "  waiting for a reachable, settled boot (up to 12 min)"
OK=0
for i in $(seq 1 48); do
  if timeout 8 adb devices 2>/dev/null | grep -qP '^\S+\tdevice$'; then
    BC=$(timeout 10 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    UP2=$(timeout 10 adb shell 'cat /proc/uptime' 2>/dev/null | awk '{print int($1)}')
    if [ "$BC" = "1" ] && [ -n "${UP2:-}" ] && [ "$UP2" -lt 900 ]; then
      echo "  boot reachable: completed=1 uptime=${UP2}s after ~$((i * 15))s"
      OK=1
      break
    fi
  fi
  sleep 15
done
if [ "$OK" != 1 ]; then
  echo "  no reachable boot after 12 min - aborting this attempt (no poll waste)"
  exit 1
fi
echo "  letting the system settle (75s)"
sleep 75

echo "== start the root shell (fifo kept open)"
IN=/tmp/aneset_in; OUT=/tmp/aneset_out
rm -f "$IN" "$OUT"; mkfifo "$IN"; : > "$OUT"
adb shell "$EXP" < "$IN" >> "$OUT" 2>&1 &
EXP_PID=$!
exec 9> "$IN"
ROOT=0
# The exploit's SELinux stage calls live_with_selinux() twice by design (the
# first call must fail to populate avc nodes, the second must succeed after
# the avc-cache rewrite) - and each call parses the policy in userspace and
# pushes the serialised image through /sys/fs/selinux/load, where the kernel
# re-parses it. On this SoC that is slow enough that a 240s poll still killed
# runs mid-stage (measured twice: killed exactly at the policydb stage with no
# error line printed). Give it fifteen minutes and never kill a progressing run.
for i in $(seq 1 900); do
  grep -q "uid=0(root)" "$OUT" 2>/dev/null && { echo "  ROOT after ${i}s"; ROOT=1; break; }
  sleep 1
done
if [ "$ROOT" != 1 ]; then
  echo ">>> exploit did not reach root this boot. tail:"
  tail -8 "$OUT"
  exec 9>&-
  kill "$EXP_PID" 2>/dev/null
  exit 1
fi

# runroot: send one command through the fifo, print its output between markers
runroot() {
  local mark="MK$RANDOM$RANDOM" before
  before=$(wc -c < "$OUT")
  printf 'echo %s\n%s\necho %s\n' "$mark" "$1" "$mark" >&9
  for i in $(seq 1 90); do
    sleep 1
    [ "$(tail -c +$((before+1)) "$OUT" | grep -c "^$mark$")" -ge 2 ] && break
  done
  tail -c +$((before+1)) "$OUT" | awk -v m="$mark" 'BEGIN{n=0} {if ($0==m){n++; next} if (n==1) print}'
}

echo "== set the property and switch the live gadget"
runroot 'setprop persist.sys.usb.config mtp,adb; echo setprop_rc=$?'
runroot 'echo -n mtp,adb > /data/property/persist.sys.usb.config; echo file_rc=$?'
runroot 'sleep 1; setprop sys.usb.config none; sleep 1; setprop sys.usb.config mtp,adb; echo switch_rc=$?'
echo "== verify (through the root shell)"
runroot 'getprop persist.sys.usb.config; getprop sys.usb.config; cat /data/property/persist.sys.usb.config; echo'

exec 9>&-
kill "$EXP_PID" 2>/dev/null

echo
echo "== verify (unprivileged read)"
timeout 10 adb shell getprop persist.sys.usb.config
