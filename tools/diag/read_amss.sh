#!/bin/bash
# The version check reads OEMINFO_AMSS_VER_TYPE as well as the system version.
# We only added the system version to SOFTWARE_VER_LIST.mbn. Find the device's
# actual AMSS / modem / board identifiers so they can be added too.
set -u
echo "########## baseband / modem / board properties"
timeout 60 adb shell '
for p in gsm.version.baseband gsm.sim.operator.alpha ro.build.version.baseband \
         ro.baseband ro.boot.baseband ro.hardware ro.board.platform ro.boot.hardware \
         ro.product.board ro.product.device ro.build.product ro.build.id \
         ro.build.display.id ro.build.version.incremental ro.build.version.release \
         ro.vendor.build.version.incremental ro.custom.build.version ro.confg.hw_ver \
         ro.comp.hw.ver ro.build.description ro.product.name ro.product.model \
         ro.oeminfo.version ro.build.oeminfo.version; do
  v=$(getprop $p)
  [ -n "$v" ] && echo "$p = $v"
done' 2>&1
echo
echo "########## every property mentioning amss / ver / modem / board (name only, sample)"
timeout 90 adb shell 'getprop | grep -iE "amss|modem|baseband|verlist|oemsbl" | head -40' 2>&1
echo
echo "########## a broad sample of ro.* properties for version-like strings"
timeout 90 adb shell 'getprop | grep -E "^\[ro\." | grep -iE "ver|build|board|cust|hw" | head -50' 2>&1
