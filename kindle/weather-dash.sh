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
# dashboard. To exit: tap the screen (or press any button).
# ---------------------------------------------------------------------------

# Run from a copy in /var/tmp (RAM). Plugging in USB unmounts /mnt/us; a script
# running from there gets cut off mid-run and could leave the Kindle UI paused.
if [ "$0" != /var/tmp/weather-dash.sh ]; then
  cp -f "$0" /var/tmp/weather-dash.sh && exec /bin/sh /var/tmp/weather-dash.sh "$@"
fi

# Where the rendered screens live (GitHub Pages).
BASE_URL="https://dquog.github.io/kindle-weather-dashboard"
SCREENS="dashboard tfl"   # PNG names, shown in this order

SCREEN_MINUTES=2     # how long each screen stays up before switching
TRIGGER_MINUTES=15   # ask GitHub for a fresh render this often (needs the token file)
AUTO_EXIT_MINUTES=10 # safety net: exit by itself after this long (0 = run until tapped)
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
cp -f "$FBINK" /var/tmp/dash-fbink && chmod +x /var/tmp/dash-fbink && FBINK=/var/tmp/dash-fbink
cp -f "$FONT" /var/tmp/dash-font.ttf && FONT=/var/tmp/dash-font.ttf

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
  [ -n "$CLEANED_UP" ] && return
  CLEANED_UP=1
  log "exiting, restoring Kindle UI"
  pkill -f "dd if=/dev/input/" 2>/dev/null   # stop the input watchers
  rm -f "$PIDFILE"
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
  gui_start
}
# Restore the UI on any exit (normal, error, tap-to-exit, power button, Stop tile).
trap cleanup EXIT
trap 'exit 0' TERM INT
trap '' HUP

# True while the Kindle's USB storage (/mnt/us) is mounted on the Kindle itself.
# When a computer connects in USB-drive mode it gets unmounted; then we hand back.
# In USB-drive mode /mnt/us can stay listed as mounted while its files vanish,
# so check that our own files are still visible too.
userstore_ok() {
  [ -f /mnt/us/dashboard/weather-dash.sh ] || return 1
  [ -r /proc/mounts ] || return 0
  grep -q ' /mnt/us ' /proc/mounts
}

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

# Tap the screen (or press a button) to exit. The paused Kindle UI isn't reading
# input, so we watch the input devices ourselves: the first event ends the loop.
find_input_devices() {
  devs=""
  if [ -r /proc/bus/input/devices ]; then
    devs=$(awk '/^N: Name=/ { name = tolower($0) }
      /^H: Handlers=/ { if (name ~ /touch|cyttsp|zforce|pt_mt|elan|wacom|power|gpio|key/) {
        sub(/^H: Handlers=/, ""); for (i = 1; i <= NF; i++) if ($i ~ /^event[0-9]+$/) print "/dev/input/" $i } }' \
      /proc/bus/input/devices)
  fi
  [ -n "$devs" ] || devs=$(ls /dev/input/event* 2>/dev/null)
  echo $devs
}

start_exit_watcher() {
  loop_pid=$$
  for d in $(find_input_devices); do
    # Short grace period so the tap that launched the tile can't count.
    ( sleep 3
      dd if="$d" of=/dev/null bs=16 count=1 2>/dev/null || exit 0
      echo "$(date '+%Y-%m-%d %H:%M:%S') input on $d, exiting"
      pkill -f "com.lab126.powerd goingToScreenSaver" 2>/dev/null   # wake the loop's wait
      kill -TERM "$loop_pid" 2>/dev/null ) &
  done
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
    *goingToScreenSaver*) log "power button pressed"; exit 0 ;;
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

# Record the input devices (for troubleshooting) and start watching them.
[ -r /proc/bus/input/devices ] && cp -f /proc/bus/input/devices /mnt/us/dashboard/input-devices.txt 2>/dev/null
log "tap-to-exit watching: $(find_input_devices)"
start_exit_watcher

trigger_render
load_clock_box
set -- $SCREENS
count=$#; idx=0; changes=0; minute=0

while true; do
  if ! userstore_ok; then
    log "USB storage connected; handing the screen back"
    exit 0
  fi

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
  if [ "$AUTO_EXIT_MINUTES" -gt 0 ] && [ "$minute" -ge "$AUTO_EXIT_MINUTES" ]; then
    log "safety timer: exiting after $AUTO_EXIT_MINUTES minutes"
    exit 0
  fi
  if [ $((minute % TRIGGER_MINUTES)) -eq 0 ]; then
    lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
    trigger_render
    load_clock_box
  fi

  # Wake on the next minute boundary so the clock flips on time.
  wait_or_exit $((60 - $(date +%S | sed 's/^0//')))
done
