#!/bin/sh
# ---------------------------------------------------------------------------
# Kindle e-ink weather dashboard — display loop
# Fetches the PNG rendered by GitHub Actions and shows it full-screen via FBInk.
# Runs on a jailbroken Kindle Paperwhite 7th gen (1072x1448). Best plugged in.
#
# Started/stopped by the "Weather Dashboard" / "Stop Weather Dashboard"
# library tiles (scriptlets in /mnt/us/documents).
#
# While running, the stock Kindle UI is paused so it can't draw over the
# dashboard. To exit: press the power button (or hold it ~15s to restart).
# ---------------------------------------------------------------------------

# Your GitHub Pages dashboard URL
URL="https://dquog.github.io/kindle-weather-dashboard/dashboard.png"

INTERVAL=1800        # seconds between refreshes (1800 = 30 min). Lower = fresher, more battery.
FULL_EVERY=4         # flashing full-screen refresh every Nth update (clears e-ink ghosting)
FBINK=/mnt/us/libkh/bin/fbink
TMP=/tmp/kindle-dash.png
PIDFILE=/tmp/weatherdash.pid

# Locate fbink if it isn't where WinterBreak usually puts it.
[ -x "$FBINK" ] || FBINK=$(command -v fbink 2>/dev/null)
if [ -z "$FBINK" ] || [ ! -x "$FBINK" ]; then
  echo "fbink not found. Edit FBINK= in this script to its full path." >&2
  exit 1
fi

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Pause / resume the stock Kindle UI (same approach KOReader uses).
gui_stop() {
  if [ -f /etc/upstart/lab126_gui.conf ]; then stop lab126_gui >/dev/null 2>&1
  else /etc/init.d/framework stop >/dev/null 2>&1; fi
}
gui_start() {
  if [ -f /etc/upstart/lab126_gui.conf ]; then start lab126_gui >/dev/null 2>&1
  else /etc/init.d/framework start >/dev/null 2>&1; fi
}

cleanup() {
  log "exiting, restoring Kindle UI"
  rm -f "$PIDFILE"
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
  gui_start
  exit 0
}
trap cleanup TERM INT
trap '' HUP

echo $$ > "$PIDFILE"   # the loop records its own PID so Start/Stop can find it
log "loop started (pid $$)"

# Let the library finish redrawing after the tile closes, then take over the screen.
sleep 4
gui_stop
log "stock UI paused"
sleep 2
lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null

count=0
while true; do
  lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null

  if curl -fsSL --max-time 60 -o "$TMP" "$URL"; then
    if [ "$((count % FULL_EVERY))" -eq 0 ]; then
      "$FBINK" -q -c -f                         # periodic flashing full refresh
    fi
    "$FBINK" -q -g file="$TMP",halign=CENTER,valign=CENTER
    log "displayed (update #$count)"
  else
    log "fetch failed; will retry next cycle"
    "$FBINK" -q -y 2 -m "Dashboard offline - retrying..."
  fi
  count=$((count + 1))

  # Wait for the next refresh, exiting early if the power button is pressed.
  # If lipc-wait-event returns too fast (unsupported flag etc.), fall back to sleep.
  started=$(date +%s)
  EV=""
  if command -v lipc-wait-event >/dev/null 2>&1; then
    EV=$(lipc-wait-event -s "$INTERVAL" com.lab126.powerd goingToScreenSaver 2>/dev/null)
  fi
  case "$EV" in
    *goingToScreenSaver*) log "power button pressed"; cleanup ;;
  esac
  waited=$(( $(date +%s) - started ))
  if [ "$waited" -lt 5 ]; then
    sleep "$INTERVAL" & wait $!
  fi
done
