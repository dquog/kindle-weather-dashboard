#!/bin/sh
# ---------------------------------------------------------------------------
# Kindle e-ink weather dashboard — display loop
# Fetches the PNG rendered by GitHub Actions and shows it full-screen via FBInk.
# Runs on a jailbroken Kindle Paperwhite 7th gen (1072x1448). Best plugged in.
#
# Run it from kterm (or KUAL) with:   sh /mnt/us/dashboard/weather-dash.sh
# Stop it with Ctrl-C (in kterm) or by killing the process.
# ---------------------------------------------------------------------------

# Your GitHub Pages dashboard URL
URL="https://dquog.github.io/kindle-weather-dashboard/dashboard.png"

INTERVAL=1800        # seconds between refreshes (1800 = 30 min). Lower = fresher, more battery.
FULL_EVERY=4         # flashing full-screen refresh every Nth update (clears e-ink ghosting)
FBINK=/mnt/us/libkh/bin/fbink
TMP=/tmp/kindle-dash.png

# Locate fbink if it isn't where WinterBreak usually puts it.
[ -x "$FBINK" ] || FBINK=$(command -v fbink 2>/dev/null)
if [ -z "$FBINK" ] || [ ! -x "$FBINK" ]; then
  echo "fbink not found. Edit FBINK= in this script to its full path." >&2
  exit 1
fi

echo "Weather dashboard starting. URL: $URL"
echo "Refresh every ${INTERVAL}s, full refresh every ${FULL_EVERY}th update. Ctrl-C to stop."

count=0
"$FBINK" -c -f >/dev/null 2>&1   # start with one clean flashing clear

while true; do
  # Keep the device awake and WiFi on (ignored if unsupported on your firmware).
  lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null
  lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null

  if curl -fsSL --max-time 60 -o "$TMP" "$URL"; then
    if [ "$((count % FULL_EVERY))" -eq 0 ]; then
      "$FBINK" -c -f >/dev/null 2>&1            # periodic flashing full refresh
    fi
    "$FBINK" -q -g file="$TMP",halign=CENTER,valign=CENTER
    echo "$(date '+%H:%M') displayed (update #$count)"
  else
    echo "$(date '+%H:%M') fetch failed; will retry next cycle" >&2
    "$FBINK" -q -y 2 -m "Dashboard offline - retrying..."
  fi

  count=$((count + 1))
  sleep "$INTERVAL"
done
