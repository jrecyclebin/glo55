#!/usr/bin/env bash
# Single-monitor functional test: drives a real glo55 with xdotool and
# checks window geometry, focus, workspaces, collapse, close and exec.
# Writes screenshots to ../screenshots/. Exit status 0 = all checks passed.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-functional.log
make -C "$ROOT" -s build/glo55 || exit 1
trap cleanup EXIT
start_x 1 1024x700
start_wm

echo "== second WM must refuse to start"
out=$(GLO55_DEBUG= "$ROOT/build/glo55" -c "$ROOT/test/config-default.toml" 2>&1); rc=$?
eq "second instance exit code" 1 "$rc"
check "second instance logs 'another window manager'" grep -q "another window manager" <<<"$out"

echo "== open four clients"
launch_term termA
xeyes -geometry 100x100+5+5 & sleep 0.5
xclock -geometry 100x100+5+5 & sleep 0.5
launch_term termB
# titles: xeyes/xclock set their own; order of opening: A, eyes, clock, B => stack order [B | clock, eyes, A]
eq "master (newest, termB) client geometry"  "11 37 544 652" "$(geo termB)"
eq "stack slot 1 (xclock)"                  "569 37 444 208"  "$(geo xclock)"
eq "stack slot 2 (xeyes)"                   "569 259 444 208" "$(geo xeyes)"
eq "stack slot 3 (termA)"                   "569 481 444 208" "$(geo termA)"
shot 01-tiled-with-toolbar.png

echo "== focus follows mouse"
hover termA;  eq "hover termA"  termA "$(focused)"
hover xeyes;  eq "hover xeyes"  xeyes "$(focused)"
hover termB;  eq "hover termB"  termB "$(focused)"

echo "== keyboard focus navigation (Mod = Super)"
key super+l;  eq "focus right from master -> middle stack window" xeyes "$(focused)"
key super+j;  eq "focus down" termA "$(focused)"
key super+j;  eq "focus down at bottom stays" termA "$(focused)"
key super+k;  eq "focus up" xeyes "$(focused)"
key super+k;  eq "focus up again" xclock "$(focused)"
key super+h;  eq "focus left -> master" termB "$(focused)"
read -r gx gy gw gh <<<"$(geo termB)"; eval "$(xdotool getmouselocation --shell)"
check "pointer was warped into the focused window ($X,$Y in $gx,$gy ${gw}x$gh)" test $X -ge $gx -a $X -le $((gx+gw)) -a $Y -ge $gy -a $Y -le $((gy+gh))

echo "== move windows in the layout"
key super+l;  # focus xeyes
key super+shift+h
eq "xeyes moved to master"         "11 37 544 652"  "$(geo xeyes)"
eq "termB took xeyes' stack slot"  "569 259 444 208" "$(geo termB)"
eq "focus stayed on moved window"  xeyes "$(focused)"
key super+shift+l
eq "move right swaps back (xeyes)" "569 259 444 208" "$(geo xeyes)"
eq "move right swaps back (termB)" "11 37 544 652"  "$(geo termB)"

echo "== workspaces"
key super+2
for w in termA termB xeyes xclock; do eq "$w hidden on workspace 2" IsUnviewable "$(state $w)"; done
launch_term termW
eq "single window on workspace 2 fills the area" "11 37 1002 652" "$(geo termW)"
shot 02-workspace-web.png
key super+shift+3
eq "termW warped away (hidden)" IsUnviewable "$(state termW)"
key super+3
eq "termW visible on workspace 3" IsViewable "$(state termW)"
check "workspace 3 is empty of other windows" test "$(state termA)" = IsUnviewable
key super+1
for w in termA termB xeyes xclock; do eq "$w back on workspace 1" IsViewable "$(state $w)"; done
eq "termW not on workspace 1" IsUnviewable "$(state termW)"
eq "layout restored after round trip" "11 37 544 652" "$(geo termB)"

echo "== roll up (collapse) a stack window"
hover xclock
key super+m
# the client stays mapped (but is parked out of sight): only the frame shrinks to a bar
eq "xclock rolled up: frame is a 20px bar at the bottom of the stack" "566 672 450 20" "$(fgeo xclock)"
eq "stack windows share the space above the bar: xeyes" "569 37 444 305" "$(geo xeyes)"
eq "stack windows share the space above the bar: termA" "569 356 444 305" "$(geo termA)"
eq "master untouched" "11 37 544 652" "$(geo termB)"
eq "focus moved to the nearest normal window" xeyes "$(focused)"
shot 03-collapsed.png
cp "$SHOTS/03-collapsed.png" "$SHOTS/13-rolled-default.png"

echo "== rolled windows are focusable"
key super+j;  eq "focus down: termA" termA "$(focused)"
key super+j;  eq "focus down again: the rolled bar xclock" xclock "$(focused)"
key super+j;  eq "nothing below the bar" xclock "$(focused)"
key super+h;  eq "focus left from the bar: master" termB "$(focused)"
hover_bar xclock;  eq "focus follows the mouse onto a bar" xclock "$(focused)"
hover xeyes;       eq "... and off it again" xeyes "$(focused)"

echo "== unroll: restore keybinding on a focused bar"
hover_bar xclock
key super+shift+m
eq "xclock unrolled and back in its slot" "569 37 444 208" "$(geo xclock)"
eq "stack back to three equal slots (xeyes)" "569 259 444 208" "$(geo xeyes)"
eq "xclock has focus" xclock "$(focused)"

echo "== roll up the master: the next window takes over"
hover termB
key super+m
eq "termB is a bar at the bottom of the stack column" "566 672 450 20" "$(fgeo termB)"
eq "xclock is the new master" "11 37 544 652" "$(geo xclock)"
key super+shift+m
eq "termB unrolled: master again" "11 37 544 652" "$(geo termB)"
eq "xclock back in the stack" "569 37 444 208" "$(geo xclock)"

echo "== one window left: it fills the width, the bars go under it"
hover xclock; key super+m
hover xeyes;  key super+m
hover termA;  key super+m
# bars in list order: xclock, xeyes, termA (20px each, 8px gaps) under termB, full width
eq "bar xclock" "8 616 1008 20" "$(fgeo xclock)"
eq "bar xeyes"  "8 644 1008 20" "$(fgeo xeyes)"
eq "bar termA"  "8 672 1008 20" "$(fgeo termA)"
eq "termB fills the width above the bars" "11 37 1002 568" "$(geo termB)"
shot 15-rolled-single-remaining.png

echo "== every window rolled up"
hover termB; key super+m
eq "four bars, bottom of the work area: termB first" "8 588 1008 20" "$(fgeo termB)"
eq "last bar ends one gap above the bottom" "8 672 1008 20" "$(fgeo termA)"
shot 16-rolled-all.png

echo "== restore them one by one (most recent first), original order comes back"
for i in 1 2 3 4; do key super+shift+m; done
eq "termB master" "11 37 544 652" "$(geo termB)"
eq "xclock slot 1" "569 37 444 208" "$(geo xclock)"
eq "xeyes slot 2" "569 259 444 208" "$(geo xeyes)"
eq "termA slot 3" "569 481 444 208" "$(geo termA)"

echo "== a focused bar can be closed"
launch_term termX                      # opens as master: [X | B, ...]
hover termX                            # (focus follows the mouse)
key super+m                            # roll it up
check "termX is a bar" test "$(fgeo termX | awk '{print $4}')" = 20
hover_bar termX
key super+shift+c; sleep 0.8
eq "rolled termX closed" none "$(state termX)"
eq "layout back to normal: termB master" "11 37 544 652" "$(geo termB)"

echo "== close focused window"
hover termA
key super+shift+c; sleep 0.5
eq "termA closed" none "$(state termA)"
eq "layout re-tiled: xeyes grew" "569 370 444 319" "$(geo xeyes)"

echo "== client dies on its own (DestroyNotify)"
pkill xclock; sleep 0.6
eq "xclock gone" none "$(state xclock)"
eq "stack filled by xeyes" "569 37 444 652" "$(geo xeyes)"

echo "== exec binding falls back to xterm when kitty is missing"
n0=$(xdotool search --onlyvisible --class xterm | wc -l)
key super+shift+Return; sleep 1
n1=$(xdotool search --onlyvisible --class xterm | wc -l)
eq "a new terminal appeared" $((n0+1)) "$n1"
check "fallback was logged" grep -q "kitty is not on PATH: falling back to xterm" "$LOG"
shot 04-after-exec.png

echo "== quit"
key super+shift+q; sleep 0.6
check "WM exited" bash -c "! kill -0 $WMPID 2>/dev/null"
check "no X errors/crashes in log (log.error lines)" bash -c "! grep -q ERROR '$LOG'"
echo "-- WM log tail:"; tail -n 12 "$LOG"
echo "== $PASS passed, $FAIL failed"
exit $((FAIL>0))
