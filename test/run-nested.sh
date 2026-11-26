#!/usr/bin/env bash
# Run Glo55 on a throwaway X display so you can try it without touching your
# real session.
#
#   test/run-nested.sh                 # Xephyr window on :9 (falls back to Xvfb if no host X)
#   MONITORS=2 test/run-nested.sh      # two side-by-side screens (Xinerama) for multi-monitor tests
#   DEMO=1 test/run-nested.sh          # also start a few demo clients (xterm, xeyes, xclock)
#   HEADLESS=1 test/run-nested.sh      # force Xvfb (no window)
#   CONFIG=test/config-bluesteel.toml test/run-nested.sh   # the E16 BlueSteel theme
#   NESTED_DISPLAY=:5 SIZE=1280x800 CONFIG=my.toml test/run-nested.sh
#
# Stop with Ctrl-C or Mod+Shift+Q inside the WM. Talk to it from another shell with
#   DISPLAY=:9 xdotool ...   /   DISPLAY=:9 xterm &
set -euo pipefail
cd "$(dirname "$0")/.."

D="${NESTED_DISPLAY:-:9}"
SIZE="${SIZE:-1024x700}"
MONITORS="${MONITORS:-1}"
CONFIG="${CONFIG:-config.toml}"
# The box clock is UTC; show local time in the toolbar clock (config.toml can override).
export TZ="${TZ:-America/Denver}"

make -s build/glo55

screens=()
for _ in $(seq "$MONITORS"); do screens+=(-screen "$SIZE"); done

if [ -z "${HEADLESS:-}" ] && command -v Xephyr >/dev/null && [ -n "${DISPLAY:-}" ] \
   && xdpyinfo >/dev/null 2>&1; then
    echo "Using Xephyr on $D (host display $DISPLAY), $MONITORS monitor(s)"
    Xephyr "$D" "${screens[@]}" +xinerama -ac -br -noreset &
else
    echo "Using Xvfb on $D (headless), $MONITORS monitor(s)"
    xvfb_screens=()
    for i in $(seq 0 $((MONITORS - 1))); do xvfb_screens+=(-screen "$i" "${SIZE}x24"); done
    Xvfb "$D" "${xvfb_screens[@]}" +xinerama -ac -noreset &
fi
XPID=$!
trap 'kill $XPID 2>/dev/null || true' EXIT

for _ in $(seq 100); do DISPLAY="$D" xdpyinfo >/dev/null 2>&1 && break; sleep 0.1; done

export DISPLAY="$D"
if [ -n "${DEMO:-}" ]; then
    # start the clients a moment after the WM is up
    ( sleep 1; xterm -title "xterm one" & sleep 0.3; xeyes & sleep 0.3; xclock & sleep 0.3; xterm -title "xterm two" & ) &
fi
echo "Display $D is up; starting glo55 (Mod+Shift+Q quits). Launch clients with: DISPLAY=$D xterm &"
./build/glo55 -c "$CONFIG"
