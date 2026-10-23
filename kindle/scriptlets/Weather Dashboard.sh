#!/bin/sh
# Name: Weather Dashboard
# Author: Dara
# Icon: /mnt/us/dashboard/icon.png
# DontUseFBInk

# Starts the e-ink weather dashboard in the background.
# To exit, tap "Stop Weather Dashboard" in your library.
PIDFILE=/tmp/weatherdash.pid
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  exit 0   # already running
fi
if command -v setsid >/dev/null 2>&1; then
  setsid /bin/sh /mnt/us/dashboard/weather-dash.sh > /tmp/weatherdash.log 2>&1 < /dev/null &
else
  nohup /bin/sh /mnt/us/dashboard/weather-dash.sh > /tmp/weatherdash.log 2>&1 < /dev/null &
fi
echo $! > "$PIDFILE"
