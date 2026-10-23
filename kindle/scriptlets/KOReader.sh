#!/bin/sh
# Name: KOReader
# Author: KOReader
# Icon: /mnt/us/koreader/resources/koreader.png
# DontUseFBInk

# Launches KOReader in its normal mode: it freezes the stock Kindle UI while it
# runs and resumes it instantly on exit (Menu > Exit). Detached so the tile can
# close without taking KOReader with it.
LOG=/mnt/us/koreader/launch.log
echo "$(date '+%Y-%m-%d %H:%M:%S') tile tapped" > "$LOG"
if command -v setsid >/dev/null 2>&1; then
  setsid /bin/sh /mnt/us/koreader/koreader.sh >> "$LOG" 2>&1 < /dev/null &
else
  ( nohup /bin/sh /mnt/us/koreader/koreader.sh >> "$LOG" 2>&1 < /dev/null & )
fi
exit 0
