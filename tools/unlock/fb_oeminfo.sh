#!/bin/bash
# Read the device's REAL identity from oeminfo, not from the build string.
#
# The dload updater compares the package's compatibility list (SOFTWARE_VER_LIST.mbn,
# which for our 8.0.0.110(C635) package holds "ANNEC00B000" / "ANE-BD 1.0.0.x")
# against oeminfo. On a second-hand unit the build string can say C635 while oeminfo
# says something else, which would explain "Incompatibility with current version".
#
# Earlier sweeps showed a narrow fastboot allow-list, so each verb's error is recorded
# rather than assumed: "Command not allowed" means blocked, anything else means it ran.
set -u
echo "=== rebooting to bootloader ==="
adb reboot bootloader 2>&1
for i in $(seq 1 20); do sleep 2; timeout 10 fastboot devices 2>/dev/null | grep -q . && break; done
echo "--- devices:"; timeout 10 fastboot devices 2>&1

run() { printf '%-42s : ' "$1"; timeout 25 fastboot $2 2>&1 | head -4 | tr '\n' ' '; echo; }

echo
echo "########## identity / version verbs"
run "oem get-bootinfo"            "oem get-bootinfo"
run "oem lock-state info"         "oem lock-state info"
run "oem get-product-model"       "oem get-product-model"
run "oem get-build-number"        "oem get-build-number"
run "getvar product"              "getvar product"
run "getvar vendorcountry"        "getvar vendorcountry"
run "getvar max-download-size"    "getvar max-download-size"

echo
echo "########## oeminfo reads (the decisive ones)"
run "oem oeminforead-CUSTOM_VERSION"  "oem oeminforead-CUSTOM_VERSION"
run "oem oeminforead-SYSTEM_VERSION"  "oem oeminforead-SYSTEM_VERSION"
run "oem oeminforead-CUST_VERSION"    "oem oeminforead-CUST_VERSION"
run "oem oeminforead-BOARD_VERSION"   "oem oeminforead-BOARD_VERSION"
run "oem oeminforead-VENDOR_COUNTRY"  "oem oeminforead-VENDOR_COUNTRY"

echo
echo "########## return to Android"
timeout 30 fastboot reboot 2>&1
sleep 30
timeout 20 adb devices -l 2>&1
