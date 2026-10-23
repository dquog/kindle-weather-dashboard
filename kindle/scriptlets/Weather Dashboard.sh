#!/bin/sh
# Name: Weather Dashboard
# Author: Dara
# Icon: /mnt/us/dashboard/icon.png
# DontUseFBInk

# Tap to show the dashboard full-screen. Every tap restarts it.
# To exit: press the power button (or tap "Stop Weather Dashboard").
LOG=/mnt/us/dashboard/weatherdash.log
PIDFILE=/tmp/weatherdash.pid

# Keep the log small (reset past ~100 KB).
[ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 100000 ] && : > "$LOG"

# Replace any previous loop (it may be asleep between refreshes).
[ -f "$PIDFILE" ] && kill -9 "$(cat "$PIDFILE")" 2>/dev/null
pkill -9 -f weather-dash.sh 2>/dev/null
pkill -f "com.lab126.powerd goingToScreenSaver" 2>/dev/null
rm -f "$PIDFILE"

# Make sure the normal Kindle UI is running before we start, so a failed
# start can never leave the screen blank. The new loop pauses it again.
if [ -f /etc/upstart/lab126_gui.conf ]; then start lab126_gui >/dev/null 2>&1
else /etc/init.d/framework start >/dev/null 2>&1; fi

echo "$(date '+%Y-%m-%d %H:%M:%S') tile tapped, starting loop" >> "$LOG"
if command -v setsid >/dev/null 2>&1; then
  setsid /bin/sh /mnt/us/dashboard/weather-dash.sh >> "$LOG" 2>&1 < /dev/null &
else
  ( nohup /bin/sh /mnt/us/dashboard/weather-dash.sh >> "$LOG" 2>&1 < /dev/null & )
fi
exit 0
