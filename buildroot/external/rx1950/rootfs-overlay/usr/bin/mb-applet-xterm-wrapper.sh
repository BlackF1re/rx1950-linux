#!/bin/sh
# Small-screen xterm profile: readable bitmap font, scrollbar and useful history.
export DISPLAY="${DISPLAY:-:0.0}"
exec xterm -ut -title Terminal -fn 6x10 -geometry 38x27 -sb -rightbar -sl 1000 "$@"
