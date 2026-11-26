#!/usr/bin/env bash
# Two-monitor functional test (Xephyr with two screens + Xinerama).
# Checks monitor detection, per-monitor toolbars and work areas, that windows
# open on (and key bindings act on) the monitor the pointer is on, and that
# each monitor has its own independent workspaces.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-multimonitor.log
make -C "$ROOT" -s build/glo55 || exit 1
trap cleanup EXIT
start_x 2 800x600
start_wm

check "WM found 2 monitors" grep -q "found 2 monitor(s)" "$LOG"
check "monitor 0 geometry logged" grep -q "monitor 0: 800x600+0+0, 5 workspaces" "$LOG"
check "monitor 1 geometry logged" grep -q "monitor 1: 800x600+800+0, 10 workspaces" "$LOG"
tb=$(xwininfo -root -tree | grep -c "800x26+")
eq "two toolbar windows (one per monitor)" 2 "$tb"

echo "== windows open on the monitor the pointer is on"
pmove 400 300; sleep 0.3
launch_term termA; launch_term termB
pmove 1200 300; sleep 0.3
launch_term termC; launch_term termD
# monitor 0 work area: y 26.., 800x574; master 0.55: avail_w=800-24=776 -> 426 ; client x=8+3
eq "termB master on monitor 0"        "11 37 420 552" "$(geo termB)"
eq "termA stack on monitor 0"         "445 37 344 552" "$(geo termA)"
eq "termD master on monitor 1 (x offset 800)" "811 37 420 552" "$(geo termD)"
eq "termC stack on monitor 1"         "1245 37 344 552" "$(geo termC)"
shot 05-two-monitors-tiled.png

echo "== workspaces are per monitor"
pmove 1200 300; sleep 0.3
key super+2
eq "monitor 1 switched: termC hidden" IsUnviewable "$(state termC)"
eq "monitor 1 switched: termD hidden" IsUnviewable "$(state termD)"
eq "monitor 0 unaffected: termA visible" IsViewable "$(state termA)"
eq "monitor 0 unaffected: termB visible" IsViewable "$(state termB)"
check "monitor 1 workspace named 'browser'" grep -q 'monitor 1: workspace "browser"' "$LOG"
launch_term termE
eq "new window lands on monitor 1's current workspace (full area)" "811 37 778 552" "$(geo termE)"
pmove 400 300; sleep 0.3
key super+3
check "monitor 0 workspace 'code' (monitor 0 keys act on monitor 0)" grep -q 'monitor 0: workspace "code"' "$LOG"
eq "monitor 0 switched: termA hidden" IsUnviewable "$(state termA)"
eq "monitor 1's termD stays hidden" IsUnviewable "$(state termD)"
eq "monitor 1's termE stays visible" IsViewable "$(state termE)"
launch_term termF
eq "termF fills monitor 0's 'code' workspace" "11 37 778 552" "$(geo termF)"
key super+6   # monitor 0 only has 5 workspaces: must be rejected
check "invalid workspace rejected with log.error" grep -q "monitor 0 has no workspace 6" "$LOG"
shot 06-two-monitors-different-workspaces.png
pmove 1200 300; sleep 0.3
key super+shift+9   # monitor 1 has 10 workspaces: warp termE to workspace 9
eq "monitor 1 warp: termE hidden" IsUnviewable "$(state termE)"
eq "monitor 0 unaffected by monitor 1 warp: termF visible" IsViewable "$(state termF)"
pmove 400 300; sleep 0.3
key super+1
pmove 1200 300; sleep 0.3
key super+1
eq "back on workspace 1: termC visible on monitor 1" IsViewable "$(state termC)"
eq "layout intact on monitor 1" "1245 37 344 552" "$(geo termC)"
eq "termE (warped to ws 9) still hidden" IsUnviewable "$(state termE)"

echo "== focus follows the mouse across monitors"
hover termB; eq "hover termB (monitor 0)" termB "$(focused)"
hover termC; eq "hover termC (monitor 1)" termC "$(focused)"
key super+h; eq "focus left on monitor 1 -> its master" termD "$(focused)"

echo "== quit"
key super+shift+q; sleep 0.6
check "WM exited" bash -c "! kill -0 $WMPID 2>/dev/null"
check "no log.error lines" bash -c "! grep -v 'has no workspace' '$LOG' | grep -q ERROR"
echo "== $PASS passed, $FAIL failed"
exit $((FAIL>0))
