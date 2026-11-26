#!/usr/bin/env bash
# pinkline theme test: white panels with the pink tab and line over a black
# drop edge, and the auto-hiding bottom bar. Hidden, the bar is a 7px pink
# line over black at the bottom of the screen and only that strip is kept
# clear of windows; it slides up (26px, workspaces and clock) while the
# pointer is on it and for reveal_ms after a workspace switch. Screenshots.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-pinkline.log
make -C "$ROOT" -s build/glo55 || exit 1
trap 'cleanup; rm -rf "$TMP"' EXIT
TMP=$(mktemp -d)
start_x 1 1024x768
start_wm "$ROOT/test/config-pinkline.toml"
await_win() { for _ in $(seq 60); do [ "$(state "$1")" = IsViewable ] && return; sleep 0.1; done; }
px() { convert "$1" -depth 8 -format "%[fx:int(255*p{$2,$3}.r+0.5)] %[fx:int(255*p{$2,$3}.g+0.5)] %[fx:int(255*p{$2,$3}.b+0.5)]" info:; }
pixel() { import -window root "$TMP/p.png"; px "$TMP/p.png" "$1" "$2"; }
PINK="247 0 135"; BLACK="0 0 0"; WHITE="255 255 255"; GREY="180 180 180"
# the bar's X window: "y height" from its last shown / hidden log line
barwin() { grep -E 'monitor 0 toolbar (shown|hidden):' "$LOG" | tail -1 | sed 's/.*: //' | awk -F: '{print $2, $4}'; }
bar_state() { grep -E 'monitor 0 toolbar (shown|hidden):' "$LOG" | tail -1 | sed -E 's/.*toolbar (shown|hidden):.*/\1/'; }
away() { pmove 500 300; nudge; sleep 0.4; }

echo "== theme loaded; font and images"
check "pinkline theme loaded" grep -q "themes/pinkline/theme.toml" "$LOG"
check "the bundled PinkPixel font is registered" grep -q 'font "PinkPixel' "$LOG"
check "every image loaded" test -z "$(grep 'cannot load image' "$LOG")"
check "one 26px toolbar" grep -q "toolbar(s), \\[26\\]px" "$LOG"
eq "the bar's rect is the bottom 26px" "0:742:1024:26" "$(grep 'monitor 0 toolbar rect:' "$LOG" | tail -1 | sed 's/.*rect: //')"

echo "== hidden: a 7px pink line over black along the bottom"
away
eq "the hidden strip is 7px at the bottom" "$PINK" "$(pixel 500 761)"
eq "the line is 2px" "$PINK" "$(pixel 500 762)"
eq "black under the line" "$BLACK" "$(pixel 500 763)"
eq "black to the bottom edge" "$BLACK" "$(pixel 500 767)"
check "above the strip is desktop, not the bar" test "$(pixel 500 750)" != "$BLACK"

echo "== geometry: insets L4 T8 R4 B10, gap 10, work area above the strip"
launch_term termA; await_win termA
eq "single window client" "14 18 996 723" "$(geo termA)"
eq "its frame is the cell (761 - 2 gaps high)" "10 10 1004 741" "$(fgeo termA)"
xclock -geometry 100x100+5+5 -bg white & await_win xclock; sleep 0.6
read -r fx fy fw fh <<<"$(fgeo xclock)"
read -r ux uy uw uh <<<"$(fgeo termA)"
check "focused window is xclock (the new one)" test "$(focused)" = xclock

echo "== panels: white, pink tab and line when focused, grey when not, black drop edge"
import -window root "$TMP/now.png"
eq "the panel is white" "$WHITE" "$(px "$TMP/now.png" $((fx + 2)) $((fy + 2)))"
eq "focused tab is pink (top right)" "$PINK" "$(px "$TMP/now.png" $((fx + fw - 3)) $((fy + 3)))"
eq "white left of the tab" "$WHITE" "$(px "$TMP/now.png" $((fx + fw - 16)) $((fy + 3)))"
eq "focused bottom line is pink" "$PINK" "$(px "$TMP/now.png" $((fx + fw / 2)) $((fy + fh - 7)))"
eq "black drop edge under the line" "$BLACK" "$(px "$TMP/now.png" $((fx + fw / 2)) $((fy + fh - 3)))"
eq "the notch sits on the line" "$WHITE" "$(px "$TMP/now.png" $((fx + 12)) $((fy + fh - 7)))"
eq "unfocused tab is grey" "$GREY" "$(px "$TMP/now.png" $((ux + uw - 3)) $((uy + 3)))"
eq "unfocused bottom line is grey" "$GREY" "$(px "$TMP/now.png" $((ux + uw / 2)) $((uy + uh - 7)))"
shot 80-pinkline-hidden.png

echo "== the bar slides up while the pointer is on it"
pmove 500 766; nudge; sleep 0.5
eq "pointer on the strip: shown" shown "$(bar_state)"
eq "the shown window is the whole bar" "742 26" "$(barwin)"
import -window root "$TMP/shown.png"
eq "the pink line moved to the top of the bar" "$PINK" "$(px "$TMP/shown.png" 500 742)"
eq "black body under it" "$BLACK" "$(px "$TMP/shown.png" 500 750)"
check "the bar has the workspaces and clock (not flat black)" test "$(convert "$TMP/shown.png" -crop 1024x20+0+746 +repage -format '%[fx:standard_deviation>0.05 ? 1 : 0]' info:)" = 1
# the active workspace is a pink plate
read -r bx by bw bh <<<"$(grep 'monitor 0 toolbar workspace buttons:' "$LOG" | tail -1 | sed 's/.*buttons: //' | cut -d, -f1 | tr : ' ')"
eq "the active workspace button is pink" "$PINK" "$(px "$TMP/shown.png" $((bx + 1)) $((742 + by + 1)))"
check "five workspace buttons" test "$(grep 'monitor 0 toolbar workspace buttons:' "$LOG" | tail -1 | sed 's/.*buttons: //' | tr ',' '\n' | grep -c .)" = 5
shot 81-pinkline-shown.png
pmove 300 760; nudge; sleep 0.3
eq "moving along the bar keeps it shown" shown "$(bar_state)"
away
eq "pointer away: hidden again" hidden "$(bar_state)"
eq "back to the 7px strip" "761 7" "$(barwin)"
eq "the window's panel shows again where the bar's line was" "$WHITE" "$(pixel $((fx + 20)) 742)"

echo "== a workspace switch shows it briefly"
xdotool key super+2; sleep 0.3
eq "switching shows the bar" shown "$(bar_state)"
shot 82-pinkline-after-switch.png
sleep 1.5
eq "it goes away by itself after reveal_ms" hidden "$(bar_state)"

echo "== clicking a workspace on the shown bar"
pmove 500 766; nudge; sleep 0.4
read -r bx by bw bh <<<"$(grep 'monitor 0 toolbar workspace buttons:' "$LOG" | tail -1 | sed 's/.*buttons: //' | cut -d, -f4 | tr : ' ')"
pmove $((bx + bw / 2)) $((742 + by + bh / 2)); sleep 0.3
xdotool click 1; sleep 0.5
check "the click switches to 'chat'" grep -q 'monitor 0: workspace "chat"' "$LOG"
sleep 1.5
eq "the bar stays out past reveal_ms while the pointer is on it" shown "$(bar_state)"
away
eq "and hides when the pointer leaves" hidden "$(bar_state)"

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
