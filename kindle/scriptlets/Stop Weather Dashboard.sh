#!/bin/sh
# Name: Stop Weather Dashboard
# Author: Dara
# Icon: /mnt/us/dashboard/icon-stop.png
# DontUseFBInk

# Stops the weather dashboard and lets the Kindle sleep normally again.
PIDFILE=/tmp/weatherdash.pid
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null
  rm -f "$PIDFILE"
fi
pkill -f /mnt/us/dashboard/weather-dash.sh 2>/dev/null
lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
