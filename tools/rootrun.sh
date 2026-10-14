#!/bin/bash
# Run commands in the persistent root shell and print only the new output.
#   usage: rootrun.sh 'cmd1; cmd2'
set -u
IN=/tmp/root.in
OUT=/tmp/root.out

CMD="$1"
MARK="MRK$RANDOM$RANDOM"

# remember where output currently ends
BEFORE=$(wc -c < "$OUT")

printf 'echo %s\n%s\necho %s\n' "$MARK" "$CMD" "$MARK" > "$IN"

# wait for the closing marker past our start offset
for i in $(seq 1 60); do
  sleep 1
  if tail -c +$((BEFORE + 1)) "$OUT" 2>/dev/null | grep -q "$MARK.*$MARK\|$MARK"; then
    # the marker appears twice: once from the echo, once from the last echo.
    # If we see both (or the closing one), we're done.
    if [ "$(tail -c +$((BEFORE + 1)) "$OUT" | grep -c "$MARK")" -ge 2 ]; then
      break
    fi
  fi
done

# print everything after the first marker line, minus the trailing marker
tail -c +$((BEFORE + 1)) "$OUT" \
  | awk -v m="$MARK" 'BEGIN{n=0} {if ($0==m) {n++; next} if (n==1) print}'
