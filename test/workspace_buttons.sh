#!/usr/bin/env bash
# Workspace buttons: layout from each monitor's own workspace list, hover and
# pressed looks, redraw only on state change, click-to-switch (press and
# release on the same button), no pointer warp, plus old-style `$workspaces`
# themes. Uses the Blue Steel theme on two 1024x768 monitors (a generated
# config with fixed workspace names, so the checks don't depend on the
# sample config's icon-styled names) and screenshots the toolbar in its
# normal, hover and "other workspace active" looks.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-buttons.log
make -C "$ROOT" -s build/glo55 || exit 1
trap 'cleanup; rm -rf "$TMP"' EXIT
TMP=$(mktemp -d)
start_x 2 1024x768
restart_wm() { # restart_wm CONFIG : same X server, fresh window manager
    kill "$WMPID" 2>/dev/null; wait "$WMPID" 2>/dev/null; pkill -f "xterm -T term" 2>/dev/null; sleep 0.5
    start_wm "$1"
}
cfg_with() { # cfg_with OUT THEME WS0 WS1 : the Blue Steel config with other workspace lists
    sed -e "s#^theme = .*#theme = \"$2\"#" \
        -e "0,/^workspaces = .*/s//workspaces = $3/" \
        -e "0,/^workspaces = \[\"terminal.*/s//workspaces = $4/" "$ROOT/test/config-bluesteel.toml" >"$1"
    sed -i "s#\"themes/bluesteel/theme.toml\"#\"$ROOT/themes/bluesteel/theme.toml\"#" "$1"
}
# fixed, visible names: the checks below (width follows the label, switch
# greps) shouldn't depend on the sample config's nerd-font icon styling
cfg_with "$TMP/cfg.toml" "$ROOT/themes/bluesteel/theme.toml" \
    '["main", "web", "code", "chat", "media"]' \
    '["terminal", "browser", "documents", "4", "5", "6", "7", "8", "9", "temp"]'
start_wm "$TMP/cfg.toml"

# btn MON IDX -> "x y w h" in root coordinates (from the WM's debug log)
btn() {
    local line items x y w h
    line=$(grep "monitor $1 toolbar workspace buttons:" "$LOG" | tail -1 | sed 's/.*buttons: //')
    IFS=',' read -ra items <<<"$line"
    IFS=':' read -r x y w h <<<"${items[$2]}"
    echo "$((x + $1 * 1024)) $y $w $h"
}
nbtn() { grep "monitor $1 toolbar workspace buttons:" "$LOG" | tail -1 | sed 's/.*buttons: //' | tr ',' '\n' | grep -c .; }
mid() { read -r x y w h <<<"$(btn "$1" "$2")"; echo "$((x + w/2)) $((y + h/2))"; }
moveto() { read -r x y <<<"$(mid "$1" "$2")"; pmove "$x" "$y"; sleep 0.35; }
clickbtn() { moveto "$1" "$2"; xdotool click 1; sleep 0.7; }
crop() { # crop FILE MON IDX : the pixels of one button
    read -r x y w h <<<"$(btn "$2" "$3")"; import -window root -crop "${w}x${h}+${x}+${y}" +repage "$1"; }
differ() { [ "$(compare -metric AE "$1" "$2" null: 2>&1 | awk '{print $1}')" != 0 ]; }
repaints() { grep -c "monitor $1 toolbar repaint" "$LOG"; }
nswitch() { grep -c 'workspace "' "$LOG"; }
shot0() { shot "$1" && convert "$SHOTS/$1" -crop 1024x768+0+0 +repage "$SHOTS/$1"; }   # monitor 0 only
# tmpshot NAME: monitor 0's screenshot, kept in $TMP (only used to build the closeup)
tmpshot() { import -window root -crop 1024x768+0+0 +repage "$TMP/$1"; }
await_win() { for _ in $(seq 60); do [ "$(state "$1")" = IsViewable ] && return; sleep 0.1; done; }

echo "== buttons are laid out from each monitor's own workspace list"
eq "monitor 0 (main web code chat media): 5 buttons" 5 "$(nbtn 0)"
eq "monitor 1 (10 workspaces): 10 buttons" 10 "$(nbtn 1)"
read -r x y w h <<<"$(btn 0 4)"
eq "last button sits against the right edge of the bar (1024 - 4 region margin)" 1020 $((x + w))
eq "buttons are flush with the bar: its full height" "0 20" "$y $h"
read -r x0 y0 w0 h0 <<<"$(btn 1 0)"      # terminal
read -r x3 y3 w3 h3 <<<"$(btn 1 3)"      # 4
read -r x2 y2 w2 h2 <<<"$(btn 1 2)"      # documents
check "'terminal' button is wider than '4' (width follows the label)" test "$w0" -gt "$w3"
check "'documents' button is wider than 'terminal'" test "$w2" -gt "$w0"
read -r xa ya wa ha <<<"$(btn 1 4)"
eq "buttons are 2px apart (theme spacing)" 2 $((xa - (x3 + w3)))
tmpshot normal.png

echo "== hover and pressed looks, repainting only when the state changes"
pmove 400 400; sleep 0.4
crop /tmp/glo55-b2-normal.png 0 2
r0=$(repaints 0); m0=$(date +%M)
moveto 0 2
check "hover is logged for button 2" grep -q "monitor 0 toolbar hover: button 2" "$LOG"
crop /tmp/glo55-b2-hover.png 0 2
check "hovered button looks different" differ /tmp/glo55-b2-normal.png /tmp/glo55-b2-hover.png
tmpshot hover.png
r1=$(repaints 0)
read -r bx by bw bh <<<"$(btn 0 2)"
for dx in 3 5 7 4; do pmove $((bx + dx)) $((by + 9)); sleep 0.1; done; sleep 0.3
r2=$(repaints 0)
eq "one repaint for entering the button" $((r0 + 1)) "$r1"
if [ "$m0" = "$(date +%M)" ]; then
    eq "moving around inside the same button repaints nothing" "$r1" "$r2"
else ok "(minute rolled over during the test: clock repaint, repaint count not compared)"; fi
moveto 0 3
check "moving to the next button moves the hover" grep -q "monitor 0 toolbar hover: button 3" "$LOG"
crop /tmp/glo55-b2-after.png 0 2
check "the old button looks normal again" test "$(compare -metric AE /tmp/glo55-b2-normal.png /tmp/glo55-b2-after.png null: 2>&1 | awk '{print $1}')" = 0
pmove 400 400; sleep 0.4
check "leaving the bar clears the hover" grep -q "monitor 0 toolbar hover: button -1" "$LOG"
crop /tmp/glo55-b3-left.png 0 3
moveto 0 2
xdotool mousedown 1; sleep 0.4
check "press is logged" grep -q "monitor 0 toolbar press: button 2" "$LOG"
crop /tmp/glo55-b2-pressed.png 0 2
check "pressed button looks different from hover" differ /tmp/glo55-b2-hover.png /tmp/glo55-b2-pressed.png
check "pressed button looks different from normal" differ /tmp/glo55-b2-normal.png /tmp/glo55-b2-pressed.png
n0=$(nswitch)
xdotool mouseup 1; sleep 0.6
check "releasing on the pressed button switches to it" grep -q 'monitor 0: workspace "code"' "$LOG"
pmove 400 400; sleep 0.3

echo "== click switches that monitor's workspace; the pointer stays on the button"
# (we are on 'code' now) go back to main, then put a window there
clickbtn 0 0
check "back on 'main'" grep -q 'monitor 0: workspace "main"' "$LOG"
pmove 400 400; sleep 0.3
launch_term termA; await_win termA
n0=$(nswitch)
moveto 0 1; xdotool click 1; sleep 0.7
check "clicking 'web' switches to it" grep -q 'monitor 0: workspace "web"' "$LOG"
eq "termA (on main) is hidden" IsUnviewable "$(state termA)"
read -r mx my <<<"$(mid 0 1)"
eq "the pointer was not warped away from the button" "x:$mx y:$my" "$(xdotool getmouselocation | awk '{print $1, $2}')"
tmpshot other.png
crop /tmp/glo55-b1-active.png 0 1
crop /tmp/glo55-b0-idle.png 0 0
check "active button looks different from an idle one" differ /tmp/glo55-b1-active.png /tmp/glo55-b0-idle.png
n1=$(nswitch)
clickbtn 0 1
eq "clicking the current workspace does nothing" "$n1" "$(nswitch)"
clickbtn 0 0
eq "clicking 'main' brings termA back" IsViewable "$(state termA)"
pmove 400 400; sleep 0.3
launch_term termB; await_win termB; sleep 0.4
shot0 26-bluesteel-embedded-desktop.png
n1=$(nswitch)

echo "== cancelled and stray clicks do nothing"
moveto 0 2; xdotool mousedown 1; sleep 0.2
moveto 0 3; xdotool mouseup 1; sleep 0.5
eq "press on one button, release on another: no switch" "$n1" "$(nswitch)"
moveto 0 2; xdotool mousedown 1; sleep 0.2
pmove 400 400; sleep 0.2; xdotool mouseup 1; sleep 0.5
eq "press on a button, release off the bar: no switch" "$n1" "$(nswitch)"
read -r bx by bw bh <<<"$(btn 0 1)"
pmove $((bx + bw)) $((by + 9)); sleep 0.3; xdotool click 1; sleep 0.5
eq "click in the gap between two buttons: no switch" "$n1" "$(nswitch)"
pmove 300 10; sleep 0.3; xdotool click 1; sleep 0.5
eq "click on the bar outside the button row: no switch" "$n1" "$(nswitch)"
moveto 0 2; xdotool click 3; sleep 0.5
eq "right click on a button: no switch" "$n1" "$(nswitch)"

echo "== monitors are independent"
clickbtn 1 3
check "monitor 1 switches to workspace '4'" grep -q 'monitor 1: workspace "4"' "$LOG"
eq "monitor 0's window is untouched" IsViewable "$(state termA)"
eq "monitor 0 buttons unchanged" 5 "$(nbtn 0)"
clickbtn 1 9
check "monitor 1's 10th button is 'temp'" grep -q 'monitor 1: workspace "temp"' "$LOG"
# closeup: the right-hand buttons in three looks (idle + hover on 'code' + current workspace
# 'web'), left clock tab on top, each row 3x
convert "$TMP/normal.png" "$TMP/hover.png" "$TMP/other.png" -crop 1024x20+0+0 +repage -background '#000' -splice 0x4 -append \
    \( +clone -crop 330x72+0+0 +repage -scale 300% \) \( -clone 0 -crop 360x72+664+0 +repage -scale 300% \) -delete 0 +append \
    "$SHOTS/25-bluesteel-toolbar-embedded-closeup.png" && echo "# screenshot: screenshots/25-bluesteel-toolbar-embedded-closeup.png"

restart_wm() { # restart_wm CONFIG : same X server, fresh window manager
    kill "$WMPID" 2>/dev/null; wait "$WMPID" 2>/dev/null; pkill -f "xterm -T term" 2>/dev/null; sleep 0.5
    start_wm "$1"
}
cfg_with() { # cfg_with OUT THEME WS0 WS1 : the Blue Steel config with other workspace lists
    sed -e "s#^theme = .*#theme = \"$2\"#" \
        -e "0,/^workspaces = .*/s//workspaces = $3/" \
        -e "0,/^workspaces = \[\"terminal.*/s//workspaces = $4/" "$ROOT/test/config-bluesteel.toml" >"$1"
    sed -i "s#\"themes/bluesteel/theme.toml\"#\"$ROOT/themes/bluesteel/theme.toml\"#" "$1"
}

echo "== a different workspace list relays the buttons out (no theme change)"
cfg_with "$TMP/cfg.toml" "$ROOT/themes/bluesteel/theme.toml" '["one", "two", "three"]' '["solo"]'
restart_wm "$TMP/cfg.toml"
eq "monitor 0 now has 3 buttons" 3 "$(nbtn 0)"
eq "monitor 1 now has 1 button" 1 "$(nbtn 1)"
read -r x y w h <<<"$(btn 0 2)"
eq "still right-aligned" 1020 $((x + w))
read -r xs ys ws hs <<<"$(btn 1 0)"
eq "single button on monitor 1 is right-aligned too" $((1024 + 1020)) $((xs + ws))
clickbtn 0 2
check "third button switches to 'three'" grep -q 'monitor 0: workspace "three"' "$LOG"
tmpshot three.png

echo "== old-style themes (a \$workspaces text element) get clickable text buttons"
cat >"$TMP/legacy.toml" <<'TOML'
[[windows]]
border_width = 3

[[toolbars]]
height = 24

[toolbars.workspaces]
type    = "text"
content = "$workspaces"
font    = "monospace"
size    = 13
fore    = "#ffffff"
left    = { edge = "left", offset = 10 }
right   = { edge = "left", offset = 400 }
TOML
cfg_with "$TMP/cfg2.toml" "$TMP/legacy.toml" '["main", "web", "code"]' '["a", "b"]'
restart_wm "$TMP/cfg2.toml"
eq "legacy theme: one button per workspace" 3 "$(nbtn 0)"
read -r x y w h <<<"$(btn 0 0)"
eq "legacy buttons start at the old text's left edge" 10 "$x"
clickbtn 0 1
check "legacy text button is clickable" grep -q 'monitor 0: workspace "web"' "$LOG"
shot0 24-legacy-workspaces-text.png

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
