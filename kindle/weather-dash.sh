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
# dashboard. To exit: tap the Kindle Home button in the bottom-right corner.
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
TOUCH_DEV=/dev/input/event1   # PW3 touchscreen (per KOReader); auto-detected below if possible
HOME_PAD=24                   # extra pixels around the Home button that still count as a tap

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
  [ -n "$WATCHER_PID" ] && kill "$WATCHER_PID" 2>/dev/null   # stop the Home-button watcher
  pkill -f "dd if=/dev/input/" 2>/dev/null
  rm -f "$PIDFILE"
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
  gui_start
}
# Restore the UI on any exit (Home button, USB connected, Stop tile, error).
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

# Kindle Home button. The paused Kindle UI isn't reading the touchscreen, so we
# read raw touch events ourselves (16-byte input_event structs on this 32-bit
# Kindle) and exit only when a tap lands on the button drawn in the footer.
find_touch_device() {
  d=""
  if [ -r /proc/bus/input/devices ]; then
    d=$(awk '/^N: Name=/ { name = tolower($0) }
      /^H: Handlers=/ { if (name ~ /touch|cyttsp|zforce|pt_mt|elan/) { sub(/^H: Handlers=/, "")
        for (i = 1; i <= NF; i++) if ($i ~ /^event[0-9]+$/) { print "/dev/input/" $i; exit } } }' \
      /proc/bus/input/devices)
  fi
  echo "${d:-$TOUCH_DEV}"
}

# Home button box published by the renderer: "top left width height".
load_home_box() {
  if curl -fsS --max-time 30 -o /tmp/dash-home.txt "$BASE_URL/home.txt?t=$(date +%s)"; then
    read -r HT HL HW HH < /tmp/dash-home.txt
  fi
  HT=${HT:-1324}; HL=${HL:-724}; HW=${HW:-298}; HH=${HH:-78}
}

home_watcher() {
  dev=$1; loop_pid=$2
  if ! command -v od >/dev/null 2>&1; then
    # Can't decode tap positions: fall back to "any tap exits" rather than trap you.
    log "od not available; any tap will exit"
    dd if="$dev" of=/dev/null bs=16 count=1 2>/dev/null && kill -TERM "$loop_pid"
    return
  fi
  x1=$((HL - HOME_PAD)); x2=$((HL + HW + HOME_PAD))
  y1=$((HT - HOME_PAD)); y2=$((HT + HH + HOME_PAD))
  x=""; y=""; logged=""; fails=0
  while :; do
    # Each od line is one event: offset, sec(lo,hi), usec(lo,hi), type, code, value(lo,hi).
    events=$(dd if="$dev" bs=1024 count=1 2>/dev/null | od -v -d | awk 'NF >= 9 { printf "%d %d %d %d\n", $6, $7, $8, $2 }')
    if [ -z "$events" ]; then
      fails=$((fails + 1))
      if [ "$fails" -ge 5 ]; then
        log "can't read touch events from $dev; any tap will exit"
        dd if="$dev" of=/dev/null bs=16 count=1 2>/dev/null && kill -TERM "$loop_pid"
        return
      fi
      sleep 1; continue
    fi
    fails=0
    while read -r type code val sec; do
      case "$type:$code" in
        3:53|3:0) x=$val ;;   # ABS_MT_POSITION_X / ABS_X
        3:54|3:1) y=$val ;;   # ABS_MT_POSITION_Y / ABS_Y
        0:0)                  # SYN_REPORT: a complete touch sample
          [ -n "$x" ] && [ -n "$y" ] || continue
          if [ "$sec" != "$logged" ]; then log "touch at $x,$y"; logged=$sec; fi
          if [ "$x" -ge "$x1" ] && [ "$x" -le "$x2" ] && [ "$y" -ge "$y1" ] && [ "$y" -le "$y2" ]; then
            log "Kindle Home tapped"
            kill -TERM "$loop_pid"
            return
          fi ;;
      esac
    done <<EVENTS
$events
EVENTS
  done
}

# Sleep N seconds; a TERM (Home button, Stop tile) cuts it short right away.
wait_a_bit() {
  n=$1; [ "$n" -lt 1 ] && n=1
  sleep "$n" & wait $!
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

# Record the input devices (for troubleshooting) and watch for Home taps.
[ -r /proc/bus/input/devices ] && cp -f /proc/bus/input/devices /mnt/us/dashboard/input-devices.txt 2>/dev/null
load_home_box
TOUCH=$(find_touch_device)
log "Kindle Home button at x=$HL y=$HT (${HW}x$HH); watching $TOUCH"
home_watcher "$TOUCH" $$ &
WATCHER_PID=$!

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
  if [ $((minute % TRIGGER_MINUTES)) -eq 0 ]; then
    lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
    trigger_render
    load_clock_box
  fi

  # Wake on the next minute boundary so the clock flips on time.
  wait_a_bit $((60 - $(date +%S | sed 's/^0//')))
done
