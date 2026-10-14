#!/bin/bash
# Pull the firmware packages the user staged on Google Drive.
#
# gdown is installed into the persistent venv (this host's /tmp gets wiped, so
# nothing of value may live there). Downloads land in ~/dev/p20-root/firmware/azrom/.
set -u
cd /home/placeless/dev/p20-root
DEST=firmware/azrom
mkdir -p "$DEST"
VENV=.venv-sym
"$VENV/bin/pip" install -q gdown 2>&1 | tail -2

# id:expected-name (the first one's name is unknown, we let gdown ask)
while read -r ID NAME; do
  echo "=================================================================="
  echo "== $ID  ->  $NAME"
  echo "=================================================================="
  if [ -n "$NAME" ] && [ -f "$DEST/$NAME" ]; then
    echo "  already present: $(stat -c%s "$DEST/$NAME") bytes"
    continue
  fi
  if [ -n "$NAME" ]; then
    "$VENV/bin/gdown" "$ID" -O "$DEST/$NAME" --no-cookies 2>&1 | tail -3 || \
      "$VENV/bin/gdown" "$ID" -O "$DEST/$NAME" 2>&1 | tail -3
  else
    "$VENV/bin/gdown" "$ID" -O "$DEST/" --no-cookies 2>&1 | tail -3 || \
      "$VENV/bin/gdown" "$ID" -O "$DEST/" 2>&1 | tail -3
  fi
  ls -la "$DEST"/ | tail -6
done <<'LIST'
1pRTiJDfoYxbxZBp6ilZi9VO_EaszJtZL
13ktkOsTet-s_T9SIHjihdKuRBx0Ba7FR ANE-LX2J_Anne-L22J_8.0.0.127(C719)_Firmware_Android_8.0.0_EMUI_8.0.0.rar
1XQY4GOmy8Rfd4t4kpbeLw2n6hksU6HwQ ANE-LX2J_Anne-L22J_8.0.0.127(C719)_kddi_jp_Firmware_Android_8.0.0_EMUI8.0.0.rar
1N98pdIkbhBvL-RE-wePRWkYeOlK6oL37 ANE-L22J_Anne-L22J_8.0.0.202(C719)_Firmware_Android_8.0.0_EMUI_8.0.0_05015FCS.zip
LIST

echo
echo "############ downloaded:"
ls -la "$DEST"
df -h /home | tail -1
