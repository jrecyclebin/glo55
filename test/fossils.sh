#!/usr/bin/env bash
# Fossils of the Machines theme test: geometry with the E16 border insets
# (18/1/16/4) and the 16px toolbar, the focused/unfocused orb, the clickable
# close / minimise / fullscreen buttons (stick does nothing), the rolled-up
# 16px pipe, the embedded workspace buttons (idle / hover / active), the
# stretched desktop image, and screenshots.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-fossils.log
make -C "$ROOT" -s build/glo55 || exit 1
trap 'cleanup; rm -rf "$TMP"' EXIT
TMP=$(mktemp -d)
start_x 1 1024x768
start_wm $ROOT/test/config-fossils.toml
await_win() { for _ in $(seq 60); do [ "$(state "$1")" = IsViewable ] && return; sleep 0.1; done; }
# btn IDX -> "x y w h" of a workspace button (from the WM's debug log)
btn() { local items x y w h; IFS=',' read -ra items <<<"$(grep "monitor 0 toolbar workspace buttons:" "$LOG" | tail -1 | sed 's/.*buttons: //')"
        IFS=':' read -r x y w h <<<"${items[$1]}"; echo "$x $y $w $h"; }
moveto() { read -r x y w h <<<"$(btn "$1")"; pmove $((x + w/2)) $((y + h/2)); sleep 0.35; }
crop() { read -r x y w h <<<"$(btn "$2")"; import -window root -crop "${w}x${h}+${x}+${y}" +repage "$1"; }
differ() { [ "$(compare -metric AE "$1" "$2" null: 2>&1 | awk '{print $1}')" != 0 ]; }

echo "== theme loaded; its image, font and desktop"
check "fossils theme loaded" grep -q "themes/fossils/theme.toml" "$LOG"
check "the bundled font (Dissatisfaction) is registered" grep -q 'font "Dissatisfaction' "$LOG"
check "every image loaded" test -z "$(grep 'cannot load image' "$LOG")"
check "toolbar is 16px (the E16 pipe)" grep -q "toolbar(s), \\[16\\]px" "$LOG"
sleep 0.3
import -window root "$TMP/desk.png"
check "the desktop shows the theme's moon image (not a flat colour)" test "$(convert "$TMP/desk.png" -crop 1024x740+0+20 +repage -format '%[fx:mean>0.002 && standard_deviation>0.002 ? 1 : 0]' info:)" = 1
check "...and it is stretched to the screen: its far right edge is lit" test "$(convert "$TMP/desk.png" -crop 4x700+1020+30 +repage -format '%[fx:mean>0.004 ? 1 : 0]' info:)" = 1

echo "== geometry: insets L18 T16 R1 B4, gap 6, toolbar 16"
launch_term termA; await_win termA
# one window: cell 6,22 -> 1012x740; client = cell minus the insets
eq "single window client" "24 38 993 720" "$(geo termA)"
xeyes -geometry 100x100+5+5 & await_win xeyes
xclock -geometry 100x100+5+5 & await_win xclock
launch_term termB; await_win termB; sleep 0.6
read -r mx my mw mh <<<"$(geo termB)"
eq "master client starts at 24,38 and is as tall as the cell less the bar+bottom" "24 38 $mh" "$mx $my $mh"
eq "master client height 720" 720 "$mh"
read -r sx sy sw sh <<<"$(geo xclock)"
eq "stack column starts after master + gap + the left inset" $((mx + mw + 1 + 6 + 18)) "$sx"
eq "stack column ends at the screen edge less the gap and right inset" $((1024 - 6 - 1)) $((sx + sw))
read -r fx fy fw fh <<<"$(fgeo termB)"
eq "frame = client + insets (L18 R1 T16 B4)" "$((mx - 18)) $((my - 16)) $((mw + 19)) $((mh + 20))" "$fx $fy $fw $fh"
check "focused window is termB (the new one)" test "$(focused)" = termB

echo "== the orb: red when focused, grey when not"
crop_orb() { read -r x y w h <<<"$(fgeo "$1")"; import -window root -crop "16x16+$((x + 6))+$((y + 10))" +repage "$2"; }
crop_orb termB "$TMP/orb_focused.png"
hover xeyes; sleep 0.3
crop_orb termB "$TMP/orb_unfocused.png"
check "the orb looks different when the window loses focus" differ "$TMP/orb_focused.png" "$TMP/orb_unfocused.png"
red() { convert "$1" -format '%[fx:mean.r - mean.b]' info:; }
check "focused orb is red (red channel well above blue)" awk "BEGIN{exit !($(red "$TMP/orb_focused.png") > 0.12)}"
check "unfocused orb is not (grey)" awk "BEGIN{exit !($(red "$TMP/orb_unfocused.png") < 0.1)}"
hover termB; sleep 0.3
shot 29-fossils-tiled.png
# closeups, 3x: the focused window's pipe, an unfocused one, the toolbar's two ends
read -r fx fy fw fh <<<"$(fgeo termB)"; read -r ux uy uw uh <<<"$(fgeo xclock)"
convert "$SHOTS/29-fossils-tiled.png" \( -clone 0 -crop $((fw > 420 ? 420 : fw))x80+$fx+$fy +repage -scale 300% \) \
    \( -clone 0 -crop 440x40+$((ux + uw - 440))+$uy +repage -scale 300% \) \
    \( -clone 0 -crop 440x40+$ux+$uy +repage -scale 300% \) -delete 0 -background '#000' -append \
    "$SHOTS/30-fossils-titlebar-closeup.png" && echo "# screenshot: screenshots/30-fossils-titlebar-closeup.png"

echo "== title-bar buttons: close 56-80, minimise 80-104, ..., stick W-80, fullscreen W-56 (rightmost button)"
read -r fx fy fw fh <<<"$(fgeo termB)"
# stick (decorative): nothing happens
pmove $((fx + fw - 68)) $((fy + 8)); sleep 0.3; xdotool click 1; sleep 0.5
eq "stick button does nothing" "$fx $fy $fw $fh" "$(fgeo termB)"
check "termB is still tiled and visible" test "$(state termB)" = IsViewable
# minimise
pmove $((fx + 92)) $((fy + 8)); sleep 0.3; xdotool click 1; sleep 0.6
read -r bx by bw bh <<<"$(fgeo termB)"
eq "rolled bar is 16px high" 16 "$bh"
eq "...and sits at the bottom of the screen less the gap" $((768 - 6)) $((by + bh))
read -r gx gy gw gh <<<"$(geo xclock)"
eq "the others fill the freed space: xclock is master (full height)" "24 38 $mh" "$gx $gy $gh"
shot 31-fossils-rolled.png
convert "$SHOTS/31-fossils-rolled.png" -crop 1024x120+0+648 +repage -scale 100% "$TMP/rolled.png"
# the bar keeps close, minimise, stick, fullscreen and the pipe: unroll with minimise
pmove $((bx + 92)) $((by + 8)); sleep 0.3; xdotool click 1; sleep 0.6
read -r ux2 uy2 uw2 uh2 <<<"$(geo termB)"
eq "minimise on the rolled bar unrolls termB (master again)" "24 38 $mh" "$ux2 $uy2 $uh2"
# fullscreen: the rightmost button
read -r fx fy fw fh <<<"$(fgeo termB)"
hover termB
pmove $((fx + fw - 44)) $((fy + 8)); sleep 0.3; xdotool click 1; sleep 0.7
eq "fullscreen button: termB covers the screen" "0 0 1024 768" "$(geo termB)"
key super+f
eq "mod+f toggles it back" "24 38 $mh" "$(geo termB | awk '{print $1,$2,$4}')"
# close
hover xeyes
read -r fx fy fw fh <<<"$(fgeo xeyes)"
pmove $((fx + 68)) $((fy + 8)); sleep 0.3; xdotool click 1; sleep 0.9
eq "close button closes xeyes" none "$(state xeyes)"
# a rolled bar keeps the close button
hover termA; key super+m
read -r bx by bw bh <<<"$(fgeo termA)"
pmove $((bx + 68)) $((by + 8)); sleep 0.3; xdotool click 1; sleep 0.9
eq "close button on a rolled bar closes termA" none "$(state termA)"
# clicks in the client area do nothing
hover termB; read -r cx cy cw ch <<<"$(geo termB)"
pmove $((cx + 20)) $((cy + 20)); xdotool click 1; sleep 0.4
check "click inside a client does nothing" test "$(state termB)" = IsViewable

echo "== toolbar: embedded workspace buttons (idle / hover / active), clock on the left"
pmove 400 400; sleep 0.4
shot0() { import -window root -crop 1024x768+0+0 +repage "$1"; }
read -r x4 y4 w4 h4 <<<"$(btn 4)"
eq "5 workspace buttons" 5 "$(grep 'monitor 0 toolbar workspace buttons:' "$LOG" | tail -1 | sed 's/.*buttons: //' | tr ',' '\n' | grep -c .)"
eq "the last button ends 18px (the terminator) from the right edge" 1006 $((x4 + w4))
eq "buttons are flush with the pipe: its full 16px" "0 16" "$y4 $h4"
check "the clock is logged" grep -q "toolbar clock reads" "$LOG"
crop "$TMP/idle.png" 2; crop "$TMP/active.png" 0
check "the current workspace's button is lit (differs from an idle one)" differ "$TMP/idle.png" "$TMP/active.png"
cmp_w() { read -r _ _ w _ <<<"$(btn "$1")"; echo "$w"; }
shot0 "$TMP/t_idle.png"
moveto 2; crop "$TMP/hover.png" 2
check "hovering a button changes its look" differ "$TMP/idle.png" "$TMP/hover.png"
shot0 "$TMP/t_hover.png"
xdotool mousedown 1; sleep 0.4; crop "$TMP/pressed.png" 2
check "pressed looks different from hover" differ "$TMP/hover.png" "$TMP/pressed.png"
xdotool mouseup 1; sleep 0.7
check "releasing switches to 'code'" grep -q 'monitor 0: workspace "code"' "$LOG"
pmove 400 400; sleep 0.4
shot0 "$TMP/t_code.png"
# closeup: left end (clock) + right end (buttons) in three looks, 3x each
for n in idle hover code; do
    convert "$TMP/t_$n.png" \( -clone 0 -crop 90x16+0+0 +repage \) \( -clone 0 -crop 300x16+724+0 +repage \) -delete 0 +append -scale 300% "$TMP/row_$n.png"
done
convert "$TMP/row_idle.png" "$TMP/row_hover.png" "$TMP/row_code.png" -background '#000' -splice 0x6 -append "$SHOTS/32-fossils-toolbar-closeup.png" \
    && echo "# screenshot: screenshots/32-fossils-toolbar-closeup.png"

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
