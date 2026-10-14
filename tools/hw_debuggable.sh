#!/bin/bash
# P20 Lite (ANE-LX2J): is ANY system app debuggable?
#
# run-as only works for an app whose manifest sets android:debuggable, and it
# then gives that app's uid. A debuggable *system-signed* app therefore yields
# uid 1000 (system) - a different privilege class from shell (2000). On this
# device shell was denied connect() to /dev/socket/oeminfo_nvm, whose owner
# (oeminfo_nvm_server) is a root daemon that writes the oeminfo partition, i.e.
# where Huawei's boot/lock flags live. A system-uid foothold is the cheapest
# possible way to reach it. Read-only probing; nothing is written.
set -u
D="adb shell"

echo "################ build flags"
$D 'getprop ro.build.type; getprop ro.debuggable; getprop ro.secure; getprop ro.build.tags; id' 2>&1

echo
echo "################ system packages of interest"
$D 'pm list packages -s 2>/dev/null | sed "s/package://" | grep -iE "huawei|hw|hisilicon|factory|engineer|diag|test|nv|oeminfo|update|care|hota|seccfg|boot"' 2>&1 | sort | head -70

echo
echo "################ run-as probe over ALL system packages"
n=0; hits=0
for p in $($D 'pm list packages -s 2>/dev/null | sed "s/package://"' 2>/dev/null | tr -d '\r'); do
  n=$((n+1))
  out=$($D "run-as $p id" 2>&1 | tr -d '\r')
  case "$out" in
    *uid=*) echo "  DEBUGGABLE -> $p : $out"; hits=$((hits+1)) ;;
  esac
done
echo "  probed $n system packages, debuggable hits: $hits"

echo
echo "################ same probe over third-party packages (cheaper to be sure)"
n=0
for p in $($D 'pm list packages -3 2>/dev/null | sed "s/package://"' 2>/dev/null | tr -d '\r'); do
  n=$((n+1))
  out=$($D "run-as $p id" 2>&1 | tr -d '\r')
  case "$out" in *uid=*) echo "  DEBUGGABLE -> $p : $out" ;; esac
done
echo "  probed $n third-party packages"

echo
echo "################ can shell reach the interesting sockets at all?"
$D 'ls -la /dev/socket/ 2>&1 | head -30' 2>&1
