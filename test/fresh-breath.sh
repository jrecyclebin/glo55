#!/usr/bin/env bash
# Fresh Breath test, for all four palettes (Sedona, Painted Desert, Chillwave,
# Office Print), which share one layout (themes/fresh-breath/layout.toml): the
# theme loads with its fonts and every image; the smooth desktop is bilinear
# cover-scaled; geometry with the 15/41/11/12 insets, 40px rolled height and
# the 43px toolbar; focused vs unfocused plates (four slashes vs two); the
# title-bar buttons in mockup order (collapse, fullscreen, close); close /
# collapse / fullscreen; the rolled bar; the toolbar clock, date, rail title
# and workspace plates; and screenshots (one per palette, close-ups, a contact
# sheet).
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-fresh-breath.log
make -C "$ROOT" -s build/glo55 || exit 1
trap 'cleanup; rm -rf "$TMP"' EXIT
TMP=$(mktemp -d)
start_x 1 1024x768
await_win() { for _ in $(seq 60); do [ "$(state "$1")" = IsViewable ] && return; sleep 0.1; done; }
btn() { local items x y w h; IFS=',' read -ra items <<<"$(grep "monitor 0 toolbar workspace buttons:" "$LOG" | tail -1 | sed 's/.*buttons: //')"
        IFS=':' read -r x y w h <<<"${items[$1]}"; echo "$x $y $w $h"; }
nbtn() { grep 'monitor 0 toolbar workspace buttons:' "$LOG" | tail -1 | sed 's/.*buttons: //' | tr ',' '\n' | grep -c .; }
moveto() { read -r x y w h <<<"$(btn "$1")"; pmove $((x + w/2)) $((y + h/2)); sleep 0.35; }
crop() { read -r x y w h <<<"$(btn "$2")"; import -window root -crop "${w}x${h}+${x}+${y}" +repage "$1"; }
differ() { [ "$(compare -metric AE "$1" "$2" null: 2>&1 | awk '{print $1}')" != 0 ]; }

PALETTES=(sedona painted-desert chillwave office-print)
idx=0
for pal in "${PALETTES[@]}"; do
echo; echo "######## $pal"
LOG=/tmp/glo55-fresh-breath-$pal.log
start_wm $ROOT/test/config-fresh-breath-$pal.toml

echo "== theme loaded; fonts, images and desktop"
check "$pal theme loaded (extends the shared layout)" grep -q "themes/fresh-breath/$pal/theme.toml" "$LOG"
check "the bundled Barlow Condensed font is registered" grep -q 'font "Barlow Condensed' "$LOG"
check "every image loaded" test -z "$(grep 'cannot load image' "$LOG")"
check "toolbar is 43px" grep -q "toolbar(s), \\[43\\]px" "$LOG"
sleep 0.4
import -window root "$TMP/desk.png"; cp "$TMP/desk.png" "$TMP/desk-$pal.png"
# desktop.png is 2880x1800; cover on 1024x768 scales to 1228x768 (centred, 102px cropped each side)
convert "$ROOT/themes/fresh-breath/$pal/art/desktop.png" -filter Triangle -resize 1228x768! -crop 1024x700+102+40 +repage "$TMP/want_desk.png"
convert "$TMP/desk.png" -crop 1024x700+0+40 +repage "$TMP/got_desk.png"
rmse=$(compare -metric RMSE "$TMP/want_desk.png" "$TMP/got_desk.png" null: 2>&1 | sed 's/.*(\(.*\))/\1/')
check "the desktop is the palette's landscape, cover-scaled smoothly (RMSE $rmse < 0.03)" awk "BEGIN{exit !($rmse < 0.03)}"
check "the desktop is not a flat colour" test "$(convert "$TMP/got_desk.png" -format '%[fx:standard_deviation>0.05 ? 1 : 0]' info:)" = 1

echo "== geometry: insets L15 T41 R11 B12, gap 8, toolbar 43"
launch_term termA; await_win termA
eq "single window client" "23 92 982 656" "$(geo termA)"
eq "its frame is the cell" "8 51 1008 709" "$(fgeo termA)"
xeyes -geometry 100x100+5+5 & await_win xeyes
xclock -geometry 100x100+5+5 & await_win xclock
launch_term termB; await_win termB; sleep 0.6
read -r mx my mw mh <<<"$(geo termB)"
eq "master client starts at 23,92 and is 656 high" "23 92 656" "$mx $my $mh"
read -r sx sy sw sh <<<"$(geo xclock)"
eq "stack column: master + right inset + gap + left inset" $((mx + mw + 11 + 8 + 15)) "$sx"
eq "stack column ends at the screen edge less the gap and right inset" $((1024 - 8 - 11)) $((sx + sw))
read -r fx fy fw fh <<<"$(fgeo termB)"
eq "frame = client + insets (L15 R11 T41 B12)" "$((mx - 15)) $((my - 41)) $((mw + 26)) $((mh + 53))" "$fx $fy $fw $fh"
hover termB; sleep 0.3
check "focused window is termB (the new one)" test "$(focused)" = termB

echo "== floating title: the gap above the frame shows the desktop"
pmove 20 760; sleep 0.3
import -window root "$TMP/full.png"
read -r fx fy fw fh <<<"$(fgeo termB)"
# 4px at the top-right of the frame, past the button plate (which ends 11px in)
convert "$TMP/desk.png" -crop 4x4+$((fx + fw - 4))+$fy +repage "$TMP/gap_desk.png"
convert "$TMP/full.png" -crop 4x4+$((fx + fw - 4))+$fy +repage "$TMP/gap_win.png"
check "the frame is shaped (desktop shows past the plates)" test "$(compare -metric AE "$TMP/gap_desk.png" "$TMP/gap_win.png" null: 2>&1 | awk '{print $1}')" = 0

echo "== active vs inactive plates"
read -r ax ay aw ah <<<"$(fgeo termA)"
read -r bx by bw bh <<<"$(fgeo termB)"
convert "$TMP/full.png" -crop 200x48+$((bx + 20))+$by +repage "$TMP/foc-title.png"
convert "$TMP/full.png" -crop 200x48+$((ax + 20))+$ay +repage "$TMP/idle-title.png"
check "focused and unfocused title plates differ" differ "$TMP/foc-title.png" "$TMP/idle-title.png"

echo "== toolbar: clock, workspaces"
check "five workspace buttons were laid out" test "$(nbtn)" = 5
read -r x y w h <<<"$(btn 0)"
check "a workspace plate is at least 20px tall" test "$h" -ge 20
import -window root -crop 180x43+0+0 +repage "$TMP/clock-$pal.png"
import -window root -crop 280x43+740+0 +repage "$TMP/tabs-$pal.png"
check "the clock plate is not a flat colour" test "$(convert "$TMP/clock-$pal.png" -format '%[fx:standard_deviation>0.05 ? 1 : 0]' info:)" = 1

# screenshots of the tiled layout, before the button tests change it
shot "$((52 + idx))-fresh-breath-$pal-tiled.png"
cp "$SHOTS/$((52 + idx))-fresh-breath-$pal-tiled.png" "$TMP/shot-$pal.png"
convert "$TMP/full.png" -crop 1024x140+0+0 +repage "$SHOTS/$((56 + idx))-fresh-breath-$pal-titlebar-closeup.png" \
    && echo "# screenshot: screenshots/$((56 + idx))-fresh-breath-$pal-titlebar-closeup.png"
convert "$TMP/full.png" -crop 1024x43+0+0 +repage -scale 200% "$SHOTS/$((60 + idx))-fresh-breath-$pal-toolbar-closeup.png" \
    && echo "# screenshot: screenshots/$((60 + idx))-fresh-breath-$pal-toolbar-closeup.png"

# close-button hover / pressed close-up (chillwave, once)
if [ "$pal" = chillwave ]; then
    read -r fx fy fw fh <<<"$(fgeo termB)"
    import -window root -crop 140x50+$((fx + fw - 140))+$fy +repage "$TMP/btn-normal.png"
    pmove $((fx + fw - 30)) $((fy + 22)); sleep 0.4
    import -window root -crop 140x50+$((fx + fw - 140))+$fy +repage "$TMP/btn-hover.png"
    check "hovering close changes the button" differ "$TMP/btn-normal.png" "$TMP/btn-hover.png"
    xdotool mousedown 1; sleep 0.35
    import -window root -crop 140x50+$((fx + fw - 140))+$fy +repage "$TMP/btn-pressed.png"
    check "pressing close changes the button again" differ "$TMP/btn-hover.png" "$TMP/btn-pressed.png"
    # move off the button before release so we do not actually close termB
    pmove 20 760; sleep 0.15
    xdotool mouseup 1; sleep 0.2
    convert "$TMP/btn-normal.png" "$TMP/btn-hover.png" "$TMP/btn-pressed.png" -background '#000' -splice 8x0 -append "$SHOTS/65-fresh-breath-button-states.png" \
        && echo "# screenshot: screenshots/65-fresh-breath-button-states.png"
    # mouseup may have closed termB if release was still on close; relaunch if needed
    if [ "$(state termB)" != IsViewable ]; then
        launch_term termB; await_win termB; hover termB; sleep 0.4
    fi
fi

echo "== title-bar buttons: collapse, fullscreen, close (close is rightmost)"
# close on xclock — rightmost button, ~30px in from the right
hover xclock
read -r cfx cfy cfw cfh <<<"$(fgeo xclock)"
pmove $((cfx + cfw - 30)) $((cfy + 22)); sleep 0.3; xdotool click 1; sleep 0.5
eq "close (rightmost button) sent xclock away" none "$(state xclock)"

# collapse on xeyes — left of the three, ~110px in
hover xeyes
for off in 110 118 100; do
    read -r efx efy efw efh <<<"$(fgeo xeyes)"
    pmove $((efx + efw - off)) $((efy + 22)); sleep 0.3; xdotool click 1; sleep 0.6
    read -r rox roy row roh <<<"$(fgeo xeyes)"
    [ "$roh" = 40 ] && break
done
eq "collapse (left button) rolls xeyes up to 40px" 40 "$roh"

# unroll, then fullscreen on termB — middle button, ~70px in; the client
# covers the screen (the frame is hidden). Mod+f toggles it back.
pmove $((rox + row - 110)) $((roy + 20)); sleep 0.3; xdotool click 1; sleep 0.6
hover termB
# the □ sits near 70px in from the frame's right; try a few points in the
# middle of the button plate (left of the close cell at -67) in case the lean
# puts the hit a little off-centre on a given palette.
for off in 70 76 82; do
    read -r bfx bfy bfw bfh <<<"$(fgeo termB)"
    pmove $((bfx + bfw - off)) $((bfy + 22)); sleep 0.3; xdotool click 1; sleep 0.6
    [ "$(geo termB)" = "0 0 1024 768" ] && break
done
eq "fullscreen (middle button): termB covers the screen" "0 0 1024 768" "$(geo termB)"
key super+f
eq "mod+f toggles it back" "23 92 656" "$(geo termB | awk '{print $1,$2,$4}')"

cleanup_wm() { kill "$WMPID" 2>/dev/null; wait "$WMPID" 2>/dev/null; pkill -f "xterm -T term" 2>/dev/null; pkill xeyes 2>/dev/null; pkill xclock 2>/dev/null; sleep 0.6; }
cleanup_wm
idx=$((idx + 1))
done

echo "== contact sheet"
montage "$SHOTS/52-fresh-breath-sedona-tiled.png" "$SHOTS/53-fresh-breath-painted-desert-tiled.png"         "$SHOTS/54-fresh-breath-chillwave-tiled.png" "$SHOTS/55-fresh-breath-office-print-tiled.png"     -tile 2x2 -geometry 768x576+4+4 -background '#111' "$SHOTS/64-fresh-breath-contact-sheet.png"     && echo "# screenshot: screenshots/64-fresh-breath-contact-sheet.png"
check "contact sheet written" test -s "$SHOTS/64-fresh-breath-contact-sheet.png"

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
