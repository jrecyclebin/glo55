#!/usr/bin/env bash
# BlueSteel theme test: geometry with title-bar insets (10/20/10/10), the
# clickable close/minimise buttons, the local-time clock, and screenshots.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-bluesteel.log
make -C "$ROOT" -s build/glo55 || exit 1
trap cleanup EXIT
start_x 1 1024x768
export TZ=Etc/UTC           # the *config* must win over the environment
start_wm $ROOT/test/config-bluesteel.toml

echo "== theme loaded, insets applied (gap 6, toolbar 20, insets L10 T20 R10 B10)"
check "bluesteel theme loaded" grep -q "themes/bluesteel/theme.toml" "$LOG"
await_win() { for _ in $(seq 60); do [ "$(state "$1")" = IsViewable ] && return; sleep 0.1; done; }
launch_term termA; await_win termA
# one window: cell 6,26 -> 1012x736; client = cell minus insets
eq "single window client" "16 46 992 706" "$(geo termA)"
xeyes -geometry 100x100+5+5 & await_win xeyes
xclock -geometry 100x100+5+5 & await_win xclock
launch_term termB; await_win termB; sleep 0.5
eq "master client (termB)"    "16 46 533 706" "$(geo termB)"
eq "stack slot 1 (xclock)"    "575 46 433 212" "$(geo xclock)"
eq "stack slot 2 (xeyes)"     "575 294 433 211" "$(geo xeyes)"
eq "stack slot 3 (termA)"     "575 541 433 211" "$(geo termA)"
shot 10-bluesteel-tiled.png
# close-up of title bars (focused + unfocused) and the toolbar, 3x
convert "$SHOTS/10-bluesteel-tiled.png" \( -clone 0 -crop 1024x20+0+0 +repage -scale 200% \) \
    \( -clone 0 -crop 512x24+0+24 +repage -scale 400% \) \( -clone 0 -crop 512x24+560+24 +repage -scale 400% \) \
    -delete 0 -background '#000' -append "$SHOTS/12-bluesteel-titlebar-closeup.png" \
    && echo "# screenshot: screenshots/12-bluesteel-titlebar-closeup.png"

echo "== clock shows local time (America/Denver), not UTC"
want=$(TZ=America/Denver date +%H:%M); wantprev=$(TZ=America/Denver date -d '-1 min' +%H:%M)
utc=$(TZ=UTC date +%H:%M)
echo "# denver=$want utc=$utc"
shown=$(sed -n 's/.*toolbar clock reads \([0-9:]*\).*/\1/p' "$LOG" | head -1)
check "toolbar clock reads Denver time ($shown; UTC is $utc)" test "$shown" = "$want" -o "$shown" = "$wantprev"
check "clock is not UTC" test "$shown" != "$utc"

echo "== title-bar buttons are clickable"
hover termB
read -r cx cy cw ch <<<"$(geo termB)"
fx=$((cx - 10)); fy=$((cy - 20)); fw=$((cw + 20))
# minimise button: x = W-42 .. W-30, y = 4 .. 20
pmove $((fx + fw - 36)) $((fy + 12)); sleep 0.3; xdotool click 1; sleep 0.6
eq "minimise button rolls termB up: a 20px title-bar-only frame at the bottom of the stack" "565 742 453 20" "$(fgeo termB)"
eq "stack fills the freed space: xclock is now master" "16 46 533 706" "$(geo xclock)"
eq "xeyes above the bar" "575 46 433 322" "$(geo xeyes)"
shot 14-rolled-bluesteel.png
# the bar's minimise button unrolls it again (hover first: focus follows the mouse)
read -r bx by bw bh <<<"$(fgeo termB)"
pmove $((bx + bw - 36)) $((by + 12)); sleep 0.3; xdotool click 1; sleep 0.6
eq "clicking minimise on the bar unrolls termB" "16 46 533 706" "$(geo termB)"
# close button: x = 0 .. 16, y = 0 .. 20 of the focused window
hover termA
read -r cx cy cw ch <<<"$(geo termA)"
pmove $((cx - 10 + 8)) $((cy - 20 + 10)); sleep 0.3; xdotool click 1; sleep 0.9
eq "close button closes termA" "none" "$(state termA)"
# rolled up, a window keeps its title-bar buttons: close works on the bar
hover termB
key super+m
read -r bx by bw bh <<<"$(fgeo termB)"
pmove $((bx + 8)) $((by + 10)); sleep 0.3; xdotool click 1; sleep 0.9
eq "close button on a rolled bar closes termB" "none" "$(state termB)"
# clicking inside the client area must not trigger anything
hover xeyes
read -r cx cy cw ch <<<"$(geo xeyes)"
pmove $((cx + 20)) $((cy + 20)); xdotool click 1; sleep 0.4
check "click inside a client does nothing" test "$(state xeyes)" = IsViewable

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
