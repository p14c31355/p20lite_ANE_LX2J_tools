#!/bin/bash
# Probe the running root session for a capability-only SELinux off switch.
# /sys/fs/selinux/enforce is gated by capable(CAP_MAC_ADMIN) in the kernel,
# and we hold all capabilities - if the shell domain happens to be allowed to
# write that one file, we get system-wide permissive without touching the
# exploit's code (which is what broke the race timing).
set -u
IN=/tmp/root.in
OUT=/tmp/root.out

runroot() {
  local MARK="MK$RANDOM$RANDOM" b
  b=$(wc -c < "$OUT")
  printf 'echo %s\n%s\necho %s\n' "$MARK" "$1" "$MARK" > "$IN"
  for i in $(seq 1 45); do
    sleep 1
    [ "$(tail -c +$((b+1)) "$OUT" | grep -c "^$MARK$")" -ge 2 ] && break
  done
  tail -c +$((b+1)) "$OUT" | awk -v m="$MARK" 'BEGIN{n=0}{if($0==m){n++;next} if(n==1)print}'
}

echo "############ is the session still alive?"
runroot 'id'

echo
echo "############ what does selinuxfs look like to us"
runroot 'ls -laZ /sys/fs/selinux/ 2>&1 | head -12'

echo
echo "############ the capability-only test"
runroot 'echo 0 > /sys/fs/selinux/enforce 2>&1; echo "write-exit=$?"; cat /sys/fs/selinux/enforce 2>&1; getenforce 2>&1'

echo
echo "############ setenforce as a fallback"
runroot 'setenforce 0 2>&1; getenforce 2>&1'

echo
echo "############ if permissive worked, can we touch the partition now?"
runroot 'dd if=/dev/block/bootdevice/by-name/nvme of=/data/local/tmp/nvme_head.img bs=512 count=4 2>&1; ls -la /data/local/tmp/nvme_head.img 2>&1'

echo
echo "############ and the nvme tool"
runroot '/data/local/tmp/hisi-nve r FBLOCK 2>&1 | head -12'
