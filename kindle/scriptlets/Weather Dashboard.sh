#!/bin/sh
# Name: Weather Dashboard
# Author: Dara
# Icon: /mnt/us/dashboard/icon.png
# DontUseFBInk

# Tap to show the weather dashboard full-screen. Every tap restarts it.
# To exit: press the power button (or hold it ~15s to restart the Kindle).
LOG=/mnt/us/dashboard/weatherdash.log
PIDFILE=/tmp/weatherdash.pid

# Keep the log small (reset past ~100 KB).
[ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 100000 ] && : > "$LOG"

# Replace any previous loop (it may be asleep between refreshes).
[ -f "$PIDFILE" ] && kill -9 "$(cat "$PIDFILE")" 2>/dev/null
pkill -9 -f /mnt/us/dashboard/weather-dash.sh 2>/dev/null
pkill -f "com.lab126.powerd goingToScreenSaver" 2>/dev/null
rm -f "$PIDFILE"

echo "$(date '+%Y-%m-%d %H:%M:%S') tile tapped, starting loop" >> "$LOG"
if command -v setsid >/dev/null 2>&1; then
  setsid /bin/sh /mnt/us/dashboard/weather-dash.sh >> "$LOG" 2>&1 < /dev/null &
else
  ( nohup /bin/sh /mnt/us/dashboard/weather-dash.sh >> "$LOG" 2>&1 < /dev/null & )
fi
exit 0
