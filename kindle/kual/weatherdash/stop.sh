#!/bin/sh
# Stops the weather dashboard loop and hands the screen back to the Kindle.
PIDFILE=/tmp/weatherdash.pid
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null
  rm -f "$PIDFILE"
fi
lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
FBINK=/mnt/us/libkh/bin/fbink
[ -x "$FBINK" ] && "$FBINK" -q -c -f -m -y 20 "Dashboard stopped - tap to continue"
