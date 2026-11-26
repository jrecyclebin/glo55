#!/usr/bin/env bash
# CORPO theme test: geometry with the 3/25/3/3 frame insets and the 30px top
# toolbar, the active / inactive frame, the clickable close / collapse /
# fullscreen buttons (stick does nothing), the rolled-up 25px bar, workspace
# buttons on the LEFT and the amber LCD clock on the RIGHT, the cover-scaled
# pixel-exact desktop image, and screenshots.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-corpo.log
make -C "$ROOT" -s build/glo55 || exit 1
trap 'cleanup; rm -rf "$TMP"' EXIT
TMP=$(mktemp -d)
start_x 1 1024x768
start_wm $ROOT/test/config-corpo.toml
await_win() { for _ in $(seq 60); do [ "$(state "$1")" = IsViewable ] && return; sleep 0.1; done; }
# btn IDX -> "x y w h" of a workspace button (from the WM's debug log)
btn() { local items x y w h; IFS=',' read -ra items <<<"$(grep "monitor 0 toolbar workspace buttons:" "$LOG" | tail -1 | sed 's/.*buttons: //')"
        IFS=':' read -r x y w h <<<"${items[$1]}"; echo "$x $y $w $h"; }
nbtn() { grep 'monitor 0 toolbar workspace buttons:' "$LOG" | tail -1 | sed 's/.*buttons: //' | tr ',' '\n' | grep -c .; }
moveto() { read -r x y w h <<<"$(btn "$1")"; pmove $((x + w/2)) $((y + h/2)); sleep 0.35; }
crop() { read -r x y w h <<<"$(btn "$2")"; import -window root -crop "${w}x${h}+${x}+${y}" +repage "$1"; }
differ() { [ "$(compare -metric AE "$1" "$2" null: 2>&1 | awk '{print $1}')" != 0 ]; }
# px FILE X Y -> "r g b" of one pixel
px() { convert "$1" -depth 8 -format "%[fx:int(255*p{$2,$3}.r+0.5)] %[fx:int(255*p{$2,$3}.g+0.5)] %[fx:int(255*p{$2,$3}.b+0.5)]" info:; }
# sat FILE -> mean saturation (HSL) of an image
sat() { convert "$1" -colorspace HSL -channel G -separate +channel -format '%[fx:mean]' info:; }

echo "== theme loaded; its images, fonts and desktop"
check "corpo theme loaded" grep -q "themes/corpo/theme.toml" "$LOG"
check "both bundled fonts are registered (Pixel Times, RoundedSquare)" test "$(grep -c 'font "Pixel Times\|font "RoundedSquare' "$LOG")" -ge 2
check "every image loaded (GIF background, PNG art, generated parts)" test -z "$(grep 'cannot load image' "$LOG")"
check "toolbar is 30px (the bar art's height)" grep -q "toolbar(s), \\[30\\]px" "$LOG"
sleep 0.3
import -window root "$TMP/desk.png"
check "the desktop shows the theme's ruins image (not a flat colour)" test "$(convert "$TMP/desk.png" -crop 1024x700+0+40 +repage -format '%[fx:standard_deviation>0.05 ? 1 : 0]' info:)" = 1
# bg-ruins.gif is 500x477; "cover" on 1024x768 scales it by 1024/500 (976 high),
# centred (104px cropped top and bottom), nearest-neighbour: every pixel is a source pixel
convert "$ROOT/themes/corpo/assets/bg-ruins.gif[0]" "$TMP/src.png"
ok_px=0
for p in "100 400" "512 300" "900 600" "300 700" "700 150" "40 90"; do
    read -r X Y <<<"$p"
    want=$(px "$TMP/src.png" $((X * 500 / 1024)) $(((Y + 104) * 477 / 976)))
    got=$(px "$TMP/desk.png" "$X" "$Y")
    [ "$want" = "$got" ] && ok_px=$((ok_px + 1)) || echo "# pixel $X,$Y: want [$want] got [$got]"
done
eq "desktop pixels are the source's, cover-scaled with the aspect ratio kept and no smoothing (6 samples)" 6 "$ok_px"

echo "== geometry: insets L3 T25 R3 B3, gap 6, toolbar 30"
launch_term termA; await_win termA
# one window: cell 6,36 -> 1012x726; client = cell minus the insets
eq "single window client" "9 61 1006 698" "$(geo termA)"
xeyes -geometry 100x100+5+5 & await_win xeyes
xclock -geometry 100x100+5+5 & await_win xclock
launch_term termB; await_win termB; sleep 0.6
read -r mx my mw mh <<<"$(geo termB)"
eq "master client starts at 9,61 and is 698 high" "9 61 698" "$mx $my $mh"
read -r sx sy sw sh <<<"$(geo xclock)"
eq "stack column starts after master + gap + the left inset" $((mx + mw + 3 + 6 + 3)) "$sx"
eq "stack column ends at the screen edge less the gap and right inset" $((1024 - 6 - 3)) $((sx + sw))
read -r fx fy fw fh <<<"$(fgeo termB)"
eq "frame = client + insets (L3 R3 T25 B3)" "$((mx - 3)) $((my - 25)) $((mw + 6)) $((mh + 28))" "$fx $fy $fw $fh"
check "focused window is termB (the new one)" test "$(focused)" = termB

echo "== active and inactive frames"
bar() { read -r x y w h <<<"$(fgeo "$1")"; import -window root -crop "$((w - 100))x25+$((x + 50))+$y" +repage "$2"; }
bar termB "$TMP/bar_active.png"
bar xclock "$TMP/bar_inactive.png"
check "the focused title bar differs from an unfocused one" differ "$TMP/bar_active.png" "$TMP/bar_inactive.png"
check "the unfocused bar is much less saturated (the inactive art)" awk "BEGIN{exit !($(sat "$TMP/bar_active.png") > 1.8 * $(sat "$TMP/bar_inactive.png"))}"
bar termB "$TMP/b1.png"; hover xeyes; sleep 0.3; bar termB "$TMP/b2.png"
check "a window's bar changes when it loses focus" differ "$TMP/b1.png" "$TMP/b2.png"
hover termB; sleep 0.3
bar termB "$TMP/b3.png"
check "...and returns to the active look when it regains it" test "$(compare -metric AE "$TMP/b1.png" "$TMP/b3.png" null: 2>&1 | awk '{print $1}')" = 0
shot 33-corpo-tiled.png
read -r fx fy fw fh <<<"$(fgeo termB)"; read -r ux uy uw uh <<<"$(fgeo xclock)"
convert "$SHOTS/33-corpo-tiled.png" \( -clone 0 -crop 300x25+$fx+$fy +repage -scale 300% \) \( -clone 0 -crop 300x25+$((fx + fw - 300))+$fy +repage -scale 300% \) \
    \( -clone 0 -crop 300x25+$ux+$uy +repage -scale 300% \) \( -clone 0 -crop 300x25+$((ux + uw - 300))+$uy +repage -scale 300% \) -delete 0 \
    \( -clone 0,1 +append \) \( -clone 2,3 +append \) -delete 0-3 -background '#000' -splice 0x6 -append "$SHOTS/34-corpo-titlebar-closeup.png" \
    && echo "# screenshot: screenshots/34-corpo-titlebar-closeup.png"

echo "== title-bar buttons (right to left): fullscreen W-22, collapse W-41, stick W-60, close W-79"
read -r fx fy fw fh <<<"$(fgeo termB)"
pmove $((fx + fw - 51)) $((fy + 13)); sleep 0.3; xdotool click 1; sleep 0.5
eq "stick button does nothing" "$fx $fy $fw $fh" "$(fgeo termB)"
check "termB is still tiled and visible" test "$(state termB)" = IsViewable
pmove $((fx + fw - 32)) $((fy + 13)); sleep 0.3; xdotool click 1; sleep 0.6
read -r bx by bw bh <<<"$(fgeo termB)"
eq "collapse rolls termB up: a 25px bar" 25 "$bh"
eq "...at the bottom of the screen less the gap" $((768 - 6)) $((by + bh))
read -r gx gy gw gh <<<"$(geo xclock)"
eq "the others fill the freed space: xclock is master (full height)" "9 61 698" "$gx $gy $gh"
shot 36-corpo-rolled.png
pmove $((bx + bw - 32)) $((by + 13)); sleep 0.3; xdotool click 1; sleep 0.6
eq "collapse on the rolled bar unrolls termB (master again)" "9 61 698" "$(geo termB | awk '{print $1,$2,$4}')"
read -r fx fy fw fh <<<"$(fgeo termB)"
hover termB
pmove $((fx + fw - 14)) $((fy + 13)); sleep 0.3; xdotool click 1; sleep 0.7
eq "fullscreen button (rightmost): termB covers the screen" "0 0 1024 768" "$(geo termB)"
key super+f
eq "mod+f toggles it back" "9 61 698" "$(geo termB | awk '{print $1,$2,$4}')"
hover xeyes
read -r fx fy fw fh <<<"$(fgeo xeyes)"
pmove $((fx + fw - 70)) $((fy + 13)); sleep 0.3; xdotool click 1; sleep 0.9
eq "close button closes xeyes" none "$(state xeyes)"
hover termA; key super+m
read -r bx by bw bh <<<"$(fgeo termA)"
pmove $((bx + bw - 70)) $((by + 13)); sleep 0.3; xdotool click 1; sleep 0.9
eq "close button on a rolled bar closes termA" none "$(state termA)"
hover termB; read -r cx cy cw ch <<<"$(geo termB)"
pmove $((cx + 20)) $((cy + 20)); xdotool click 1; sleep 0.4
check "click inside a client does nothing" test "$(state termB)" = IsViewable

echo "== toolbar at the top: workspaces on the left, the amber LCD clock on the right"
pmove 400 400; sleep 0.4
shot0() { import -window root -crop 1024x768+0+0 +repage "$1"; }
eq "5 workspace buttons" 5 "$(nbtn)"
read -r x0 y0 w0 h0 <<<"$(btn 0)"; read -r x4 y4 w4 h4 <<<"$(btn 4)"
eq "the first button starts at the region's 16px (over the bar's left cap)" 16 "$x0"
eq "buttons are the slot art's 20px, centred in the 30px bar" "5 20" "$y0 $h0"
check "all five buttons are left of the clock slot (x < 936)" test $((x4 + w4)) -lt 936
check "the toolbar is at the top of the screen (window area starts below it)" test "$(geo termB | awk '{print $2}')" -ge 30
import -window root "$TMP/now.png"
amber() { convert "$TMP/now.png" -crop "70x20+936+5" +repage -format '%[fx:mean.r>0.1 && mean.r>2*mean.b ? 1 : 0]' info:; }
check "the clock slot (right) holds amber LCD digits" test "$(amber)" = 1
check "the clock text was drawn (toolbar clock log)" grep -q "toolbar clock reads" "$LOG"
check "nothing amber on the left of the bar but the lit current workspace" test "$(convert "$TMP/now.png" -crop "300x30+200+0" +repage -format '%[fx:mean.r>2*mean.b ? 1 : 0]' info:)" = 0
crop "$TMP/idle.png" 2; crop "$TMP/active.png" 0
check "the current workspace's slot is lit (differs from an idle one)" differ "$TMP/idle.png" "$TMP/active.png"
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
for n in idle hover code; do
    convert "$TMP/t_$n.png" \( -clone 0 -crop 380x30+0+0 +repage \) \( -clone 0 -crop 190x30+834+0 +repage \) -delete 0 +append -scale 300% "$TMP/row_$n.png"
done
convert "$TMP/row_idle.png" "$TMP/row_hover.png" "$TMP/row_code.png" -background '#000' -splice 0x6 -append "$SHOTS/35-corpo-toolbar-closeup.png" \
    && echo "# screenshot: screenshots/35-corpo-toolbar-closeup.png"

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
