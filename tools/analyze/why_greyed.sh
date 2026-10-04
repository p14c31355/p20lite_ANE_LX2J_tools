#!/bin/bash
# Ask the framework directly: why is the toggle disabled?
#  - dumpsys oem_lock        (OemLockService's own view)
#  - dumpsys device_policy   (a device owner / MDM greys "OEM unlocking" too -
#                             and this is a second-hand unit)
#  - any management apps installed
set -u
echo "############ oem_lock service state"
timeout 60 adb shell 'dumpsys oem_lock 2>&1 | head -20; service list 2>/dev/null | grep -i oem' 2>&1 | head -25

echo
echo "############ device policy / device owner"
timeout 60 adb shell 'dumpsys device_policy 2>&1 | grep -iE "owner|admin|managed|user" | head -12' 2>&1

echo
echo "############ settings that gate it"
timeout 60 adb shell 'settings get global oem_unlock_allowed; settings get global development_settings_enabled; settings get secure user_setup_complete; getprop sys.oem_unlock_allowed; getprop ro.device_owner' 2>&1

echo
echo "############ management / admin packages"
timeout 90 adb shell 'pm list packages -e 2>/dev/null | grep -iE "mdm|emm|device.*policy|admin|airwatch|mobileiron|intune|kiosk|family|parental" | head -10; echo ---; pm list packages -d 2>/dev/null | head -5' 2>&1

echo
echo "############ is the previous owner's account still there?"
timeout 60 adb shell 'dumpsys account 2>&1 | grep -iE "account \{|name=" | head -10' 2>&1
