#!/bin/sh
# ---------------------------------------------------------------------------
# Kindle e-ink dashboard — display loop
# Cycles between the weather and TfL screens rendered by GitHub Actions, and
# draws a live clock into the header every minute. Uses FBInk.
# Runs on a jailbroken Kindle Paperwhite 7th gen (1072x1448). Best plugged in.
#
# Started/stopped by the "Weather Dashboard" / "Stop Weather Dashboard"
# library tiles (scriptlets in /mnt/us/documents).
#
# While running, the stock Kindle UI is paused so it can't draw over the
# dashboard. To exit: press the power button (or hold it ~15s to restart).
# ---------------------------------------------------------------------------

# Where the rendered screens live (GitHub Pages).
BASE_URL="https://dquog.github.io/kindle-weather-dashboard"
SCREENS="dashboard tfl"   # PNG names, shown in this order

SCREEN_MINUTES=2     # how long each screen stays up before switching
TRIGGER_MINUTES=15   # ask GitHub for a fresh render this often (needs the token file)
FULL_EVERY=6         # flashing full-screen refresh every Nth screen change (clears ghosting)

# Optional: a fine-grained GitHub token (Actions: read & write on this repo only).
# With it, the Kindle triggers renders itself instead of waiting on GitHub's timer.
TOKEN_FILE=/mnt/us/dashboard/github-token.txt
REPO=dquog/kindle-weather-dashboard
WORKFLOW=update-dashboard.yml

FBINK=/mnt/us/libkh/bin/fbink
FONT=/mnt/us/dashboard/fonts/NotoSans-Bold.ttf
SCREEN_W=1072
CLOCK_PX=83          # FBInk line height that gives digits the same height as the header title
CLOCK_NUDGE=-3       # line-top offset from the clock box so digits share the title's baseline
PIDFILE=/tmp/weatherdash.pid

# Locate fbink if it isn't where WinterBreak usually puts it.
[ -x "$FBINK" ] || FBINK=$(command -v fbink 2>/dev/null)
if [ -z "$FBINK" ] || [ ! -x "$FBINK" ]; then
  echo "fbink not found. Edit FBINK= in this script to its full path." >&2
  exit 1
fi
[ -f "$FONT" ] || FONT=/mnt/us/koreader/fonts/noto/NotoSans-Bold.ttf

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

# Ask GitHub Actions to re-render now (no-op without a token file).
trigger_render() {
  [ -s "$TOKEN_FILE" ] || return 0
  token=$(tr -d ' \r\n' < "$TOKEN_FILE")
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST \
    -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW/dispatches" \
    -d '{"ref":"main"}')
  log "asked GitHub for a fresh render (HTTP $code)"
}

# Clock box published by the renderer: "top left width height".
load_clock_box() {
  if curl -fsS --max-time 30 -o /tmp/dash-clock.txt "$BASE_URL/clock.txt?t=$(date +%s)"; then
    read -r CT CL CW CH < /tmp/dash-clock.txt
  fi
  CT=${CT:-46}; CL=${CL:-832}; CW=${CW:-190}; CH=${CH:-62}
}

draw_clock() {
  "$FBINK" -q -m -t regular="$FONT",px=$CLOCK_PX,top=$((CT + CLOCK_NUDGE)),left=$CL,right=$((SCREEN_W - CL - CW)),padding=HORIZONTAL \
    "$(date +%H:%M)"
}

# Fetch a screen (falling back to the last good copy) and draw it.
show_screen() {
  name=$1; flash=$2; img=/tmp/dash-$name.png
  if curl -fsSL --max-time 60 -o "$img.new" "$BASE_URL/$name.png?t=$(date +%s)"; then
    mv -f "$img.new" "$img"
  else
    log "fetch of $name failed; showing last copy"
  fi
  [ -s "$img" ] || return 1
  if [ "$flash" = 1 ]; then "$FBINK" -q -c -f; fi
  "$FBINK" -q -g file="$img",halign=CENTER,valign=CENTER
  draw_clock
}

# Sleep N seconds, exiting early if the power button is pressed.
# If lipc-wait-event returns too fast (unsupported flag etc.), sleep the rest.
wait_or_exit() {
  n=$1; [ "$n" -lt 1 ] && n=1
  started=$(date +%s)
  EV=""
  if command -v lipc-wait-event >/dev/null 2>&1; then
    EV=$(lipc-wait-event -s "$n" com.lab126.powerd goingToScreenSaver 2>/dev/null)
  fi
  case "$EV" in
    *goingToScreenSaver*) log "power button pressed"; cleanup ;;
  esac
  left=$(( n - ($(date +%s) - started) ))
  [ "$left" -gt 0 ] && { sleep "$left" & wait $!; }
}

echo $$ > "$PIDFILE"   # the loop records its own PID so Start/Stop can find it
log "loop started (pid $$)"

# Let the library finish redrawing after the tile closes, then take over the screen.
sleep 4
gui_stop
log "stock UI paused"
sleep 2
lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null
lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null

trigger_render
load_clock_box
set -- $SCREENS
count=$#; idx=0; changes=0; minute=0

while true; do
  # Every SCREEN_MINUTES (and on the first pass): switch to the next screen.
  if [ $((minute % SCREEN_MINUTES)) -eq 0 ]; then
    eval "name=\${$((idx + 1))}"
    flash=0; [ $((changes % FULL_EVERY)) -eq 0 ] && flash=1
    show_screen "$name" "$flash" && log "showing $name"
    idx=$(( (idx + 1) % count )); changes=$((changes + 1))
  else
    draw_clock
  fi

  minute=$((minute + 1))
  if [ $((minute % TRIGGER_MINUTES)) -eq 0 ]; then
    lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
    trigger_render
    load_clock_box
  fi

  # Wake on the next minute boundary so the clock flips on time.
  wait_or_exit $((60 - $(date +%S | sed 's/^0//')))
done
