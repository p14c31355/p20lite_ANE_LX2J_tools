#!/bin/bash
# Night watchdog (cron, no_agent): relaunch any piece of the verification loop
# that died (runner, heartbeat, queue refill, stall watch, event watch, the
# cheap USB-mode test).  The exploit-driven usbflow is deliberately NOT in the
# list tonight: its SELinux stage failed three attempts in a row, each attempt
# burns an adb window, and the cheap setprop test answers the same question in
# one second.  The usbflow script stays on disk for the morning.
# stdout is delivered verbatim and should stay EMPTY when everything is fine;
# a line is printed only when a restart was taken.
# The loop retires itself at 06:00 (the refill at 05:40); after that this
# watchdog only reports, never resurrects.
cd /home/placeless/dev/p20-root || exit 0
# next occurrence of a wall-clock time, today or tomorrow (a naive
# "today 06:00" is in the past for every evening launch, which would make
# the watchdog a no-op exactly when it is needed).
next_at() { local t n; t=$(date -d "today $1" +%s); n=$(date +%s); [ "$n" -ge "$t" ] && t=$(date -d "tomorrow $1" +%s); echo "$t"; }
now=$(date +%s)
# Resurrect dead loop pieces everywhere except the morning quiet window
# [06:00, 12:00): before 06:00 the loop is still working, after 12:00 a new
# session may have been launched - but between the two, a dead loop is
# supposed to stay dead.
h=$(date +%H)
stop_loop=0; stop_refill=0
if [ "$h" -ge 6 ] && [ "$h" -lt 12 ]; then stop_loop=1; stop_refill=1; fi
if [ "$h" -eq 5 ]; then stop_refill=1; fi
msg=""

restart() {  # $1 = pgrep pattern, $2 = script
  if ! pgrep -f "$1" >/dev/null 2>&1; then
    nohup bash "$2" >/dev/null 2>&1 &
    msg="${msg:+$msg; }$2 relaunched"
  fi
}

if [ "$now" -lt "$stop_loop" ]; then
  restart "bash ane_night.sh" ane_night.sh
  restart "bash ane_heartbeat.sh" ane_heartbeat.sh
  restart "bash ane_stall_watch.sh" ane_stall_watch.sh
  restart "bash ane_watch_event.sh" ane_watch_event.sh
  restart "bash ane_screen_watch.sh" ane_screen_watch.sh
  restart "bash ane_l2_watch.sh" ane_l2_watch.sh
  restart "bash ane_fast_catcher.sh" ane_fast_catcher.sh
  if [ ! -f usb_runs/usbcheap_verdict.txt ]; then
    restart "bash ane_usbcheap_test.sh" ane_usbcheap_test.sh
  fi
  if [ "$now" -lt "$stop_refill" ]; then
    restart "bash ane_loop_refill.sh" ane_loop_refill.sh
  fi
fi
if [ -n "$msg" ]; then
  echo "ANE night watchdog $(date '+%H:%M'): $msg"
fi
exit 0
