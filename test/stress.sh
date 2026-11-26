#!/usr/bin/env bash
# Robustness test: many windows opening/closing quickly, windows dying while
# hidden on another workspace, rapid workspace switching. The WM must survive
# and tile what's left.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-stress.log
make -C "$ROOT" -s build/glo55 || exit 1
trap cleanup EXIT
start_x 1 1024x700
start_wm
pmove 500 350

echo "== open 12 terminals as fast as possible"
pids=()
for i in $(seq 12); do xterm -T termS$i -geometry 20x5 -e sleep 3000 & pids+=($!); done
sleep 2.5
n=$(xdotool search --onlyvisible --class xterm | wc -l)
eq "12 terminals managed and visible" 12 "$n"
check "WM still running" kill -0 $WMPID

echo "== hammer workspace switching while windows exist"
for i in 1 2 3 4 5 1 2 1 3 1; do xdotool key --delay 30 super+$i; done; sleep 0.8
check "WM survived rapid switching" kill -0 $WMPID

echo "== kill windows while they are hidden on another workspace"
key super+2
kill "${pids[0]}" "${pids[1]}" "${pids[2]}"; sleep 0.8
key super+1
n=$(xdotool search --onlyvisible --class xterm | wc -l)
eq "9 terminals remain on workspace 1" 9 "$n"

echo "== kill the rest"
for p in "${pids[@]:3}"; do kill "$p" 2>/dev/null; done; sleep 1.5
n=$(xdotool search --onlyvisible --class xterm | wc -l)
eq "no windows left" 0 "$n"
check "WM alive with an empty screen" kill -0 $WMPID
xterm -T termZ -geometry 20x5 -e sleep 3000 & sleep 0.8
eq "can still open a window afterwards" "11 37 1002 652" "$(geo termZ)"
check "no log.error lines" bash -c "! grep -q ERROR '$LOG'"
shot 07-stress-final.png
key super+shift+q
echo "== $PASS passed, $FAIL failed"
exit $((FAIL>0))
