#!/usr/bin/env bash
# geo55 theme test (the Win95-inspired desk band): the two floating silver
# bands (tabs left, meter / clock right), the raised frame, focused /
# unfocused title text, clickable collapse / fullscreen / close (close is
# rightmost), the meter and clock, and screenshots.
#
# Expectations re-baselined against the two-band geo55 theme: insets L3 T29
# R4 B4, gap 4, collapsed bar 28px, marble desktop tiled in 246px steps.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-geo55.log
make -C "$ROOT" -s build/glo55 || exit 1
trap 'cleanup; rm -rf "$TMP"' EXIT
TMP=$(mktemp -d)
start_x 1 1024x768
start_wm "$ROOT/test/config-geo55.toml"
await_win() { for _ in $(seq 60); do [ "$(state "$1")" = IsViewable ] && return; sleep 0.1; done; }
btn() { local items x y w h; IFS=',' read -ra items <<<"$(grep "monitor 0 toolbar workspace buttons:" "$LOG" | tail -1 | sed 's/.*buttons: //')"
        IFS=':' read -r x y w h <<<"${items[$1]}"; echo "$x $y $w $h"; }
nbtn() { grep 'monitor 0 toolbar workspace buttons:' "$LOG" | tail -1 | sed 's/.*buttons: //' | tr ',' '\n' | grep -c .; }
trect() { grep 'monitor 0 toolbar 1 rect:' "$LOG" | tail -1 | sed 's/.*rect: //'; }
# the workspace tabs live in the LEFT band: their positions are bar-0-relative
moveto() { read -r tx ty tw th <<<"$(grep 'monitor 0 toolbar rect:' "$LOG" | tail -1 | sed 's/.*rect: //' | tr : ' ')"
           read -r x y w h <<<"$(btn "$1")"
           pmove $((tx + x + w/2)) $((ty + y + h/2)); sleep 0.35; }
differ() { [ "$(compare -metric AE "$1" "$2" null: 2>&1 | awk '{print $1}')" != 0 ]; }
px() { convert "$1" -depth 8 -format "%[fx:int(255*p{$2,$3}.r+0.5)] %[fx:int(255*p{$2,$3}.g+0.5)] %[fx:int(255*p{$2,$3}.b+0.5)]" info:; }
# near R G B FILE X Y TOL
near() { local r g b; read -r r g b <<<"$(px "$4" "$5" "$6")"
         awk -v r="$r" -v g="$g" -v b="$b" -v er="$1" -v eg="$2" -v eb="$3" -v t="$7" \
             'BEGIN{dr=r-er;dg=g-eg;db=b-eb; if(dr<0)dr=-dr; if(dg<0)dg=-dg; if(db<0)db=-db; exit !((dr<=t)&&(dg<=t)&&(db<=t))}'
}

echo "== theme loaded; font, images and desktop"
check "geo55 theme loaded" grep -q "themes/geo55/theme.toml" "$LOG"
check "the bundled W95FA font is registered" grep -q 'font "W95FA' "$LOG"
check "every image loaded" test -z "$(grep 'cannot load image' "$LOG")"
check "two 30px bands" grep -q "toolbar(s), \\[30, 30\\]px" "$LOG"
sleep 0.4
import -window root "$TMP/desk.png"
check "the desktop shows the marble texture (variation below the bands)" test "$(convert "$TMP/desk.png" -crop 1024x700+0+40 +repage -format '%[fx:standard_deviation>0.05 ? 1 : 0]' info:)" = 1
same() { [ "$(compare -metric AE "$1" "$2" null: 2>&1 | awk '{print $1}')" = 0 ]; }
convert "$TMP/desk.png" -crop 100x60+700+100 +repage "$TMP/tile1.png"
convert "$TMP/desk.png" -crop 100x60+454+100 +repage "$TMP/tile2.png"
check "the marble is tiled: crops one 246px tile apart match exactly" same "$TMP/tile1.png" "$TMP/tile2.png"
convert "$TMP/desk.png" -crop 100x20+400+5 +repage "$TMP/gap1.png"
convert "$TMP/desk.png" -crop 100x20+646+5 +repage "$TMP/gap2.png"
check "the top strip between the bands is desktop too (they float, not full width)" same "$TMP/gap1.png" "$TMP/gap2.png"

echo "== the toolbar is two floating bands at the top"
read -r x0 y0 w0 h0 <<<"$(grep 'monitor 0 toolbar rect:' "$LOG" | tail -1 | sed 's/.*rect: //' | tr : ' ')"
read -r x1 y1 w1 h1 <<<"$(grep 'monitor 0 toolbar 1 rect:' "$LOG" | tail -1 | sed 's/.*rect: //' | tr : ' ')"
check "band rects were logged" test -n "$x0" -a -n "$x1"
check "both bands are 30px tall" test "$h0" = 30 -a "$h1" = 30
check "the left band hugs the left edge" test "$x0" = 0
check "the left band is narrower than the monitor (it floats)" test "$w0" -lt 900 -a "$w0" -gt 200
check "the right band hugs the right edge" test $((x1 + w1)) = 1024
check "there is desktop between the bands" test $((x1 - x0 - w0)) -gt 100

echo "== geometry: insets L3 T29 R4 B4, gap 4, two 30px bands"
launch_term termA; await_win termA
eq "single window client" "7 63 1009 697" "$(geo termA)"
eq "its frame is the cell" "4 34 1016 730" "$(fgeo termA)"
xeyes -geometry 100x100+5+5 & await_win xeyes
xclock -geometry 100x100+5+5 & await_win xclock
launch_term termB; await_win termB; sleep 0.6
read -r mx my mw mh <<<"$(geo termB)"
eq "master client starts at 7,63 and is 697 high" "7 63 697" "$mx $my $mh"
read -r sx sy sw sh <<<"$(geo xclock)"
eq "stack column starts after master + right inset + gap + left inset" $((mx + mw + 4 + 4 + 3)) "$sx"
eq "stack column ends at the screen edge less the gap and right inset" $((1024 - 4 - 4)) $((sx + sw))
read -r fx fy fw fh <<<"$(fgeo termB)"
eq "frame = client + insets (L3 T29 R4 B4)" "$((mx - 3)) $((my - 29)) $((mw + 7)) $((mh + 33))" "$fx $fy $fw $fh"
check "focused window is termB (the new one)" test "$(focused)" = termB

echo "== raised edge all the way around, and active vs inactive titles"
import -window root "$TMP/now.png"
# outer bevel: top-left of the focused frame is white, bottom-right is black
check "the frame's top-left pixel is the silver highlight" near 188 190 193 "$TMP/now.png" "$fx" "$fy" 15
check "the frame's bottom-right pixel is the black shadow" near 0 0 0 "$TMP/now.png" $((fx + fw - 1)) $((fy + fh - 1)) 20
check "the left edge a little down is still the light highlight" near 188 190 193 "$TMP/now.png" "$fx" $((fy + 40)) 20
check "the bottom edge in the middle is a dark shadow" near 0 0 0 "$TMP/now.png" $((fx + fw / 2)) $((fy + fh - 1)) 40
# title text: focused (black) vs unfocused (grey) — crop the title area of termB vs xclock
read -r ux uy uw uh <<<"$(fgeo xclock)"
# crop inside the face (below the 2px bevel) so the mean is the text, not the edge
convert "$TMP/now.png" -crop 200x14+$((fx + 20))+$((fy + 4)) +repage "$TMP/title_active.png"
convert "$TMP/now.png" -crop 200x14+$((ux + 20))+$((uy + 4)) +repage "$TMP/title_idle.png"
check "focused and unfocused title plates differ" differ "$TMP/title_active.png" "$TMP/title_idle.png"
# compare ink, not the mean of a wide silver plate: "termB" is shorter
# than "xclock", so a mean can hide the fact that focused ink is black
# and unfocused ink is #808080.
act=$(convert "$TMP/title_active.png" -colorspace gray -format '%[fx:minima]' info:)
idl=$(convert "$TMP/title_idle.png" -colorspace gray -format '%[fx:minima]' info:)
check "the focused title text is darker than the unfocused one" awk -v a="$act" -v i="$idl" 'BEGIN{exit !(a < 0.15 && i > 0.3 && a < i - 0.2)}'

echo "== toolbar: clock, workspaces, CPU well"
check "six workspace buttons were laid out" test "$(nbtn)" = 6
read -r bx by bw bh <<<"$(btn 0)"
check "a workspace button is at least 20px square" test "$bw" -ge 20 -a "$bh" -ge 20
# tx,ty = the right band (tabs live in the left one)
read -r tx ty tw th <<<"$(trect | tr : ' ')"
# the clock sits in its sunken inset at the right end of the band
convert "$TMP/now.png" -crop 66x22+$((tx + 198))+$((ty + 4)) +repage "$TMP/clock.png"
check "the clock plate has text (not a flat colour)" test "$(convert "$TMP/clock.png" -format '%[fx:standard_deviation>0.05 ? 1 : 0]' info:)" = 1
# the meter well is the sunken dark slot at the left end of the band
convert "$TMP/now.png" -crop 72x18+$((tx + 20))+$((ty + 6)) +repage "$TMP/meter.png"
check "the CPU well is a sunken dark meter (not flat silver)" test "$(convert "$TMP/meter.png" -colorspace gray -format '%[fx:mean<0.55 ? 1 : 0]' info:)" = 1

# screenshots before destructive clicks
shot 66-geo55-tiled.png
# title-bar + border closeup: focused left, unfocused right, 300% nearest
convert "$SHOTS/66-geo55-tiled.png" \
    \( -clone 0 -crop $((fw))x$((fh))+${fx}+${fy} +repage -crop 360x36+0+0 +repage -scale 300% \) \
    \( -clone 0 -crop $((uw))x$((uh))+${ux}+${uy} +repage -crop 360x36+0+0 +repage -scale 300% \) \
    -delete 0 -background '#3b6ea5' -splice 0x8 -append "$SHOTS/67-geo55-titlebar-closeup.png" \
    && echo "# screenshot: screenshots/67-geo55-titlebar-closeup.png"
# toolbar closeup, scaled
convert "$SHOTS/66-geo55-tiled.png" -crop $((tw + 40))x40+$((tx - 20))+0 +repage -scale 300% \
    "$SHOTS/68-geo55-toolbar-closeup.png" \
    && echo "# screenshot: screenshots/68-geo55-toolbar-closeup.png"

echo "== title-bar buttons: collapse, fullscreen, close (close is rightmost)"
# close on xclock
read -r cx cy cw ch <<<"$(fgeo xclock)"
pmove $((cx + cw - 12)) $((cy + 11)); sleep 0.3; xdotool click 1; sleep 0.7
eq "close (rightmost button) sent xclock away" "none" "$(state xclock)"
# collapse on xeyes
read -r ex ey ew eh <<<"$(fgeo xeyes)"
pmove $((ex + ew - 48)) $((ey + 11)); sleep 0.3; xdotool click 1; sleep 0.7
eq "collapse (left button) rolls xeyes up to 28px" "28" "$(fgeo xeyes | awk '{print $4}')"
# fullscreen on termB, check client geo
read -r fx fy fw fh <<<"$(fgeo termB)"
pmove $((fx + fw - 30)) $((fy + 11)); sleep 0.3; xdotool click 1; sleep 0.7
eq "fullscreen (middle button): termB covers the screen" "0 0 1024 768" "$(geo termB)"
xdotool key super+f; sleep 0.5
eq "mod+f toggles it back" "7 63 697" "$(geo termB | awk '{print $1, $2, $4}')"

echo "== workspace buttons switch on release"
moveto 3; sleep 0.2
xdotool mousedown 1; sleep 0.3; xdotool mouseup 1; sleep 0.6
check "releasing a tab switches to 'chat'" grep -q 'monitor 0: workspace "chat"' "$LOG"

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
