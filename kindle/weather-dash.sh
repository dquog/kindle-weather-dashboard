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
# While running, the stock Kindle UI is frozen so it can't draw over the
# dashboard. To exit: tap the Kindle Home button in the bottom-right corner.
# ---------------------------------------------------------------------------

# Run from a copy in /var/tmp (RAM). Plugging in USB unmounts /mnt/us; a script
# running from there gets cut off mid-run and could leave the Kindle UI paused.
if [ "$0" != /var/tmp/weather-dash.sh ]; then
  cp -f "$0" /var/tmp/weather-dash.sh && exec /bin/sh /var/tmp/weather-dash.sh "$@"
fi

# UK time with summer time built in. The Kindle's own setting can lag behind a
# clock change, so the dashboard keeps its own.
export TZ="GMT0BST,M3.5.0/1,M10.5.0"

# Where the rendered screens live (GitHub Pages).
BASE_URL="https://dquog.github.io/kindle-weather-dashboard"
SCREENS="dashboard tfl"   # PNG names, shown in this order

SCREEN_MINUTES=2     # how long each screen stays up before switching
TRIGGER_MINUTES=15   # ask GitHub for a fresh render this often (needs the token file)
FULL_EVERY=6         # flashing full-screen refresh every Nth screen change (clears ghosting)
CACHE_MAX_AGE=300    # seconds a downloaded screen counts as fresh for an instant page turn

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
BUTTON_PAD_X=6                # extra pixels around footer buttons that still count as a tap
BUTTON_PAD_Y=24               #   (small sideways: the two buttons are only 16px apart)
LUAJIT=/mnt/us/koreader/luajit                # KOReader's LuaJIT, used to grab the touchscreen
TOUCHWATCH=/mnt/us/dashboard/touchwatch.lua
FB_DUMP=/var/tmp/dash-fb.dump                 # the Kindle screen we return to on exit

# Locate fbink if it isn't where WinterBreak usually puts it.
[ -x "$FBINK" ] || FBINK=$(command -v fbink 2>/dev/null)
if [ -z "$FBINK" ] || [ ! -x "$FBINK" ]; then
  echo "fbink not found. Edit FBINK= in this script to its full path." >&2
  exit 1
fi
[ -f "$FONT" ] || FONT=/mnt/us/koreader/fonts/noto/NotoSans-Bold.ttf
cp -f "$FBINK" /var/tmp/dash-fbink && chmod +x /var/tmp/dash-fbink && FBINK=/var/tmp/dash-fbink
cp -f "$FONT" /var/tmp/dash-font.ttf && FONT=/var/tmp/dash-font.ttf
[ -x "$LUAJIT" ] && cp -f "$LUAJIT" /var/tmp/dash-luajit && chmod +x /var/tmp/dash-luajit && LUAJIT=/var/tmp/dash-luajit
[ -f "$TOUCHWATCH" ] && cp -f "$TOUCHWATCH" /var/tmp/dash-touchwatch.lua && TOUCHWATCH=/var/tmp/dash-touchwatch.lua

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Two ways to keep the stock Kindle UI from drawing over the dashboard:
#  freeze (preferred): like KOReader, grab the touchscreen, hide the status bar and
#    SIGSTOP the window manager. Resuming is instant and returns to the same screen.
#  stop (fallback): stop the whole UI job. Safe, but coming back is a slow restart.
# Freeze is only used when the touchscreen grab works, so taps can't reach the
# hidden UI underneath.
pause_ui() {
  if [ "$UI_MODE" = freeze ]; then
    cat /dev/fb0 > "$FB_DUMP" 2>/dev/null
    lipc-set-prop com.lab126.pillow disableEnablePillow disable 2>/dev/null
    killall -STOP awesome 2>/dev/null
  else
    gui_stop
  fi
}
resume_ui() {
  if [ "$UI_MODE" = freeze ]; then
    killall -CONT awesome 2>/dev/null
    [ -s "$FB_DUMP" ] && cat "$FB_DUMP" > /dev/fb0 2>/dev/null
    rm -f "$FB_DUMP"
    lipc-set-prop com.lab126.pillow disableEnablePillow enable 2>/dev/null
    "$FBINK" -q -s -f 2>/dev/null   # flash-refresh so the restored screen is crisp
  else
    gui_start
  fi
}

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
  # Stop the Home-button watcher first: that releases the touchscreen grab.
  pkill -f dash-touchwatch.lua 2>/dev/null
  [ -n "$WATCHER_PID" ] && kill "$WATCHER_PID" 2>/dev/null
  pkill -f "dd if=/dev/input/" 2>/dev/null
  # Stop a refresh in progress, so it can't draw over the restored Kindle screen.
  [ -s /tmp/dash-refresh.pid ] && kill "$(cat /tmp/dash-refresh.pid)" 2>/dev/null
  rm -f /tmp/dash-refresh.pid
  rm -f "$PIDFILE"
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
  resume_ui
}
# Restore the UI on any exit (Home button, USB connected, Stop tile, error).
trap cleanup EXIT
trap 'exit 0' TERM INT
NEXT_REQ=0
trap 'NEXT_REQ=1' USR1   # sent by the touch watcher when the next-page button is tapped
REDRAW_REQ=0
trap 'REDRAW_REQ=1' USR2 # sent by the refresh worker once a fresh render is live
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
  code=$(curl -s -o /tmp/dash-gh-reply.json -w '%{http_code}' --max-time 30 -X POST \
    -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW/dispatches" \
    -d '{"ref":"main"}')
  if [ "$code" = 204 ]; then
    log "asked GitHub for a fresh render (HTTP 204, accepted)"
  else
    # GitHub's reply says why (e.g. missing permission); it never contains the token.
    why=$(sed -n 's/.*"message": *"\([^"]*\)".*/\1/p' /tmp/dash-gh-reply.json 2>/dev/null | head -1)
    log "GitHub refused the render request (HTTP $code: ${why:-no message})"
  fi
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
# Download screen $1 to /tmp/dash-NAME.png via temp file $2 (fg or bg, so a
# foreground fetch and a background prefetch never write the same file), so a
# half-written image is never shown.
fetch_screen() {
  curl -fsSL --max-time 60 -o "/tmp/dash-$1.png.$2" "$BASE_URL/$1.png?t=$(date +%s)" &&
    mv -f "/tmp/dash-$1.png.$2" "/tmp/dash-$1.png"
}

# True if our copy of a screen was downloaded within CACHE_MAX_AGE seconds.
fresh_copy() {
  [ -s "$1" ] || return 1
  t=$(date -r "$1" +%s 2>/dev/null) || return 1
  [ $(( $(date +%s) - t )) -lt "$CACHE_MAX_AGE" ]
}

# A tapped page turn ($3 = tapped) uses our copy if it's fresh, so it's instant;
# otherwise (and on timed switches) it downloads the screen first.
show_screen() {
  name=$1; flash=$2; img=/tmp/dash-$name.png
  if [ "$3" = tapped ] && fresh_copy "$img"; then
    :
  elif ! fetch_screen "$name" fg; then
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

# Footer button boxes published by the renderer: "top left width height".
load_buttons() {
  for b in home next refresh; do
    curl -fsS --max-time 30 -o "/tmp/dash-$b.txt" "$BASE_URL/$b.txt?t=$(date +%s)" || rm -f "/tmp/dash-$b.txt"
  done
  [ -s /tmp/dash-home.txt ] && read -r HT HL HW HH < /tmp/dash-home.txt
  [ -s /tmp/dash-next.txt ] && read -r NT NL NW NH < /tmp/dash-next.txt
  [ -s /tmp/dash-refresh.txt ] && read -r RT RL RW RH < /tmp/dash-refresh.txt
  HT=${HT:-1324}; HL=${HL:-724}; HW=${HW:-298}; HH=${HH:-78}
  NT=${NT:-1324}; NL=${NL:-472}; NW=${NW:-236}; NH=${NH:-78}
  RT=${RT:-1324}; RL=${RL:-50}; RW=${RW:-406}; RH=${RH:-78}
}

# "x1 y1 x2 y2" of a button box, padded for finger slop.
padded() { echo "$(($2 - BUTTON_PAD_X)) $(($1 - BUTTON_PAD_Y)) $(($2 + $3 + BUTTON_PAD_X)) $(($1 + $4 + BUTTON_PAD_Y))"; }

# Write a short message inside the refresh button (over the Updated stamp).
draw_note() {
  "$FBINK" -q -m -t regular="$FONT",px=40,top=$((RT + 19)),left=$((RL + 10)),right=$((SCREEN_W - RL - RW + 10)),padding=HORIZONTAL \
    "$1"
}

# Runs in the background after the refresh button is tapped: ask GitHub for a
# render, wait for it to go live (stamp.txt changes), then tell the loop (USR2)
# to redraw the current screen.
refresh_worker() {
  loop_pid=$1
  if [ ! -s "$TOKEN_FILE" ]; then
    log "refresh: no GitHub token"
    draw_note "Refresh needs the GitHub token"; sleep 5
  else
    draw_note "Refreshing… about 2 min"
    old=$(curl -fsS --max-time 20 "$BASE_URL/stamp.txt?t=$(date +%s)" 2>/dev/null)
    trigger_render
    i=0; new=""
    while [ "$i" -lt 16 ]; do   # 16 x 15s = 4 minutes
      sleep 15; i=$((i + 1))
      new=$(curl -fsS --max-time 20 "$BASE_URL/stamp.txt?t=$(date +%s)" 2>/dev/null)
      [ -n "$new" ] && [ "$new" != "$old" ] && break
    done
    if [ -n "$new" ] && [ "$new" != "$old" ]; then
      log "refresh: new render is live"
    else
      log "refresh: no new render after 4 minutes"
      draw_note "Refresh timed out - try again"; sleep 5
    fi
  fi
  rm -f /tmp/dash-refresh.pid
  kill -USR2 "$loop_pid" 2>/dev/null
}

start_refresh() {
  if [ -s /tmp/dash-refresh.pid ] && kill -0 "$(cat /tmp/dash-refresh.pid)" 2>/dev/null; then
    log "refresh tapped (already refreshing)"
    return
  fi
  log "refresh tapped"
  refresh_worker "$1" &
  echo $! > /tmp/dash-refresh.pid
}

# Freeze mode: the LuaJIT helper grabs the touchscreen and reports taps.
lua_home_watcher() {
  dev=$1; loop_pid=$2
  "$LUAJIT" "$TOUCHWATCH" "$dev" home $(padded $HT $HL $HW $HH) next $(padded $NT $NL $NW $NH) \
      refresh $(padded $RT $RL $RW $RH) 2>&1 |
  while read -r kind arg1 arg2 arg3; do
    case "$kind $arg1" in
      TOUCH*)     log "touch at $arg1,$arg2" ;;
      "HIT home") log "Kindle Home tapped"; kill -TERM "$loop_pid"; break ;;
      "HIT next") log "next page tapped"; kill -USR1 "$loop_pid" ;;
      "HIT refresh") start_refresh "$loop_pid" ;;
      *)     # The grab is gone, so taps could reach the hidden UI: leave safely.
             log "touch helper stopped ($kind $arg1 $arg2 $arg3); exiting"; kill -TERM "$loop_pid"; break ;;
    esac
  done
}

# Stop mode: decode raw touch events in the shell (no grab needed; the UI is stopped).
home_watcher() {
  dev=$1; loop_pid=$2
  if ! command -v od >/dev/null 2>&1; then
    # Can't decode tap positions: fall back to "any tap exits" rather than trap you.
    log "od not available; any tap will exit"
    dd if="$dev" of=/dev/null bs=16 count=1 2>/dev/null && kill -TERM "$loop_pid"
    return
  fi
  set -- $(padded $HT $HL $HW $HH); x1=$1; y1=$2; x2=$3; y2=$4
  set -- $(padded $NT $NL $NW $NH); nx1=$1; ny1=$2; nx2=$3; ny2=$4
  set -- $(padded $RT $RL $RW $RH); rx1=$1; ry1=$2; rx2=$3; ry2=$4
  x=""; y=""; logged=""; last_next=""; last_refresh=""; fails=0
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
          fi
          if [ "$x" -ge "$nx1" ] && [ "$x" -le "$nx2" ] && [ "$y" -ge "$ny1" ] && [ "$y" -le "$ny2" ] \
             && [ "$sec" != "$last_next" ]; then
            log "next page tapped"; last_next=$sec
            kill -USR1 "$loop_pid"
          fi
          if [ "$x" -ge "$rx1" ] && [ "$x" -le "$rx2" ] && [ "$y" -ge "$ry1" ] && [ "$y" -le "$ry2" ] \
             && [ "$sec" != "$last_refresh" ]; then
            last_refresh=$sec
            start_refresh "$loop_pid"
          fi ;;
      esac
    done <<EVENTS
$events
EVENTS
  done
}

# Sleep N seconds; a TERM (Home, Stop tile), USR1 (next page) or USR2 (refresh
# done) cuts it short.
wait_a_bit() {
  n=$1; [ "$n" -lt 1 ] && n=1
  sleep "$n" & wait $!
}

echo $$ > "$PIDFILE"   # the loop records its own PID so Start/Stop can find it
log "loop started (pid $$)"

# Record the input devices (for troubleshooting) and pick how to pause the UI.
[ -r /proc/bus/input/devices ] && cp -f /proc/bus/input/devices /mnt/us/dashboard/input-devices.txt 2>/dev/null
TOUCH=$(find_touch_device)
UI_MODE=stop
if [ -x "$LUAJIT" ] && [ -f "$TOUCHWATCH" ] && pidof awesome >/dev/null 2>&1; then
  check=$("$LUAJIT" "$TOUCHWATCH" "$TOUCH" --check 2>&1) && UI_MODE=freeze || log "touch grab unavailable: $check"
fi
log "UI mode: $UI_MODE"

# Let the library finish redrawing after the tile closes.
sleep 4
load_buttons
log "buttons: refresh at x=$RL y=$RT (${RW}x$RH), next page at x=$NL y=$NT (${NW}x$NH), Home at x=$HL y=$HT (${HW}x$HH); watching $TOUCH"
# Start watching for Home taps before pausing, so the grab is in place first.
if [ "$UI_MODE" = freeze ]; then
  lua_home_watcher "$TOUCH" $$ &
  sleep 1
else
  home_watcher "$TOUCH" $$ &
fi
WATCHER_PID=$!
pause_ui
log "stock UI paused ($UI_MODE)"
sleep 1
lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null
lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null

trigger_render
load_clock_box
# Copies from an earlier run may be hours old: never show those.
rm -f /tmp/dash-*.png /tmp/dash-*.png.* /tmp/dash-refresh.pid
count=$(echo $SCREENS | wc -w); idx=0; changes=0; minute=0; on_screen=0
screen_at() { i=0; for sc in $SCREENS; do [ "$i" -eq "$1" ] && { echo "$sc"; return; }; i=$((i + 1)); done; }

# Show the next screen in the cycle ($1 = tapped for a manual page turn).
next_screen() {
  name=$(screen_at "$idx")
  flash=0; [ $((changes % FULL_EVERY)) -eq 0 ] && flash=1
  show_screen "$name" "$flash" "$1" && log "showing $name${1:+ ($1)}"
  CURRENT=$name
  idx=$(( (idx + 1) % count )); changes=$((changes + 1)); on_screen=0
  # Fetch the screen that comes next now, so a tap on the next-page button is instant.
  fetch_screen "$(screen_at "$idx")" bg 2>/dev/null &
}

next_screen
while true; do
  if ! userstore_ok; then
    log "USB storage connected; handing the screen back"
    exit 0
  fi
  if [ "$NEXT_REQ" = 1 ]; then NEXT_REQ=0; next_screen tapped; fi
  if [ "$REDRAW_REQ" = 1 ]; then
    # A refresh finished: show the fresh render of the current screen.
    REDRAW_REQ=0
    show_screen "$CURRENT" 1 && log "showing $CURRENT (refreshed)"
    fetch_screen "$(screen_at "$idx")" bg 2>/dev/null &
  fi

  # Wake on the next minute boundary so the clock flips on time
  # (a next-page tap or finished refresh wakes us early; the loop top handles it).
  wait_a_bit $((60 - $(date +%S | sed 's/^0//')))
  { [ "$NEXT_REQ" = 1 ] || [ "$REDRAW_REQ" = 1 ]; } && continue

  minute=$((minute + 1)); on_screen=$((on_screen + 1))
  if [ "$on_screen" -ge "$SCREEN_MINUTES" ]; then
    next_screen
  else
    draw_clock
  fi
  if [ $((minute % TRIGGER_MINUTES)) -eq 0 ]; then
    lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
    trigger_render
    load_clock_box
  fi
done
