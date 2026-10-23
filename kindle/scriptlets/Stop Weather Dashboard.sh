#!/bin/sh
# Name: Stop Weather Dashboard
# Author: Dara
# Icon: /mnt/us/dashboard/icon-stop.png
# DontUseFBInk

# Stops the weather dashboard and restores the normal Kindle UI and sleep.
PIDFILE=/tmp/weatherdash.pid
[ -f "$PIDFILE" ] && kill -9 "$(cat "$PIDFILE")" 2>/dev/null
pkill -9 -f weather-dash.sh 2>/dev/null
pkill -f "com.lab126.powerd goingToScreenSaver" 2>/dev/null
rm -f "$PIDFILE"
lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
if [ -f /etc/upstart/lab126_gui.conf ]; then start lab126_gui >/dev/null 2>&1
else /etc/init.d/framework start >/dev/null 2>&1; fi
echo "$(date '+%Y-%m-%d %H:%M:%S') stopped from tile" >> /mnt/us/dashboard/weatherdash.log
