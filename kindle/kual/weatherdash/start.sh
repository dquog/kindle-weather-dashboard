#!/bin/sh
# Starts the weather dashboard loop in the background (tapped from KUAL).
PIDFILE=/tmp/weatherdash.pid
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  exit 0   # already running
fi
nohup /bin/sh /mnt/us/dashboard/weather-dash.sh > /tmp/weatherdash.log 2>&1 &
echo $! > "$PIDFILE"
