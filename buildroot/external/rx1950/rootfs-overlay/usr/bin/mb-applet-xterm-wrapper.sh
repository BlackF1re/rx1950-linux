#!/bin/sh
# Use a readable full-screen-sized terminal and suppress obsolete utmp writes.

export DISPLAY="${DISPLAY:-:0.0}"
exec xterm -ut -title Terminal -fn 6x10 -geometry 38x27 "$@"
