#!/usr/bin/env bash
# mod+Tab / mod+Shift+Tab (workspace next/prev, wrapping), mod+f and the
# titlebar button (fullscreen, _NET_WM_STATE), mod+r (reload: changed config and
# theme picked up, bad config rejected, windows untouched) and mod+Shift+r
# (restart: same process, windows kept on their workspaces and slots).
# Runs Blue Steel on one 1024x768 monitor, from a private copy of the config.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-session.log
make -C "$ROOT" -s build/glo55 || exit 1
TMP=$(mktemp -d)
trap 'cleanup; rm -rf "$TMP"' EXIT
CFG="$TMP/config.toml"
# fixed workspace names: the greps below follow the wrap-around cycle; the
# sample config's nerd-font icon names would make them unreadable
sed -e "s#^theme = .*#theme = \"$ROOT/themes/bluesteel/theme.toml\"#" \
    -e '0,/^workspaces = .*/s//workspaces = ["main", "web", "code", "chat", "media"]/' \
    "$ROOT/test/config-bluesteel.toml" >"$CFG"
cp "$CFG" "$TMP/config.good"
start_x 1 1024x768
start_wm "$CFG"

await_win() { for _ in $(seq 60); do [ "$(state "$1")" = IsViewable ] && return; sleep 0.1; done; }
curws() { local w; w=$(grep 'monitor 0: workspace "' "$LOG" | tail -1 | sed 's/.*workspace "\(.*\)"/\1/'); echo "${w:-main}"; }
cid()   { xdotool search --name "^$1\$" 2>/dev/null | head -1; }
ewmh()  { xprop -id "$(cid "$1")" _NET_WM_STATE 2>/dev/null | sed 's/.*= *//; /not found/d'; }
nbtn()  { grep "monitor 0 toolbar workspace buttons:" "$LOG" | tail -1 | sed 's/.*buttons: //' | tr ',' '\n' | grep -c .; }
reload() { key super+r; sleep 0.8; }

echo "== workspace next / prev (mod+Tab, mod+Shift+Tab) wrap around the monitor's list"
launch_term termA; await_win termA
eq "starts on 'main'" main "$(curws)"
key super+Tab;       eq "mod+Tab -> web"   web   "$(curws)"
eq "termA is on 'main': hidden now" IsUnviewable "$(state termA)"
launch_term termB; await_win termB
key super+Tab;       eq "mod+Tab -> code"  code  "$(curws)"
key super+Tab;       eq "mod+Tab -> chat"  chat  "$(curws)"
key super+Tab;       eq "mod+Tab -> media" media "$(curws)"
key super+Tab;       eq "mod+Tab wraps from the last to the first" main "$(curws)"
eq "termA visible again on 'main'" IsViewable "$(state termA)"
key super+shift+Tab; eq "mod+Shift+Tab wraps from the first to the last" media "$(curws)"
key super+shift+Tab; eq "mod+Shift+Tab -> chat" chat "$(curws)"
key super+shift+Tab; key super+shift+Tab
eq "mod+Shift+Tab x2 more -> web" web "$(curws)"
eq "termB is on 'web'" IsViewable "$(state termB)"
key super+shift+Tab; eq "and back on main" main "$(curws)"

echo "== fullscreen: mod+f, the titlebar button, and the EWMH state"
launch_term termC; await_win termC; sleep 0.4
eq "two tiled windows: termC is master" "16 46 533 706" "$(geo termC)"
eq "termA fills the stack column" "575 46 433 706" "$(geo termA)"
before_c=$(geo termC); before_a=$(geo termA)
eq "not fullscreen: _NET_WM_STATE is empty" "" "$(ewmh termC)"
key super+f
eq "mod+f: client covers the whole monitor (no toolbar, no frame)" "0 0 1024 768" "$(geo termC)"
eq "its frame is the monitor too" "0 0 1024 768" "$(fgeo termC)"
check "_NET_WM_STATE_FULLSCREEN is set" test "$(ewmh termC)" = "_NET_WM_STATE_FULLSCREEN"
eq "the tiled window behind it takes the freed space" "16 46 992 706" "$(geo termA)"
eq "the focused window is the fullscreen one" termC "$(focused)"
shot 28-fullscreen.png
key super+j; eq "focus keys cannot raise another window over it" termC "$(focused)"
key super+f
eq "mod+f again: back to the tiled slot" "$before_c" "$(geo termC)"
eq "the stack is back as it was" "$before_a" "$(geo termA)"
eq "_NET_WM_STATE is cleared" "" "$(ewmh termC)"
# the titlebar's maximize button: x = W-30 .. W-18, y = 4 .. 20 of the frame
hover termC
read -r fx fy fw fh <<<"$(fgeo termC)"
pmove $((fx + fw - 24)) $((fy + 12)); sleep 0.3; xdotool click 1; sleep 0.7
eq "titlebar button: fullscreen" "0 0 1024 768" "$(geo termC)"
check "button sets _NET_WM_STATE_FULLSCREEN" test "$(ewmh termC)" = "_NET_WM_STATE_FULLSCREEN"
key super+f
eq "mod+f restores after the button" "$before_c" "$(geo termC)"
# a client asking for it (wmctrl sends the _NET_WM_STATE client message)
if command -v wmctrl >/dev/null; then
    wmctrl -i -r "$(cid termA)" -b add,fullscreen; sleep 0.6
    eq "client request (add): fullscreen" "0 0 1024 768" "$(geo termA)"
    wmctrl -i -r "$(cid termA)" -b remove,fullscreen; sleep 0.6
    eq "client request (remove): back" "$before_a" "$(geo termA)"
    wmctrl -i -r "$(cid termA)" -b toggle,fullscreen; sleep 0.6
    eq "client request (toggle): fullscreen" "0 0 1024 768" "$(geo termA)"
    key super+f
    eq "mod+f takes it out again" "$before_a" "$(geo termA)"
else echo "# wmctrl not installed: client-message part skipped"; fi
# closeup of the Blue Steel title bar with the new button (focused + unfocused window)
hover termC; sleep 0.3
import -window root "$TMP/full.png"
read -r fx fy fw fh <<<"$(fgeo termC)"; read -r ax ay aw ah <<<"$(fgeo termA)"
convert "$TMP/full.png" \( -clone 0 -crop 112x24+$((fx + fw - 112))+$fy +repage -scale 600% \) \
    \( -clone 0 -crop 112x24+$((ax + aw - 112))+$ay +repage -scale 600% \) \
    -delete 0 -background '#000' -append "$SHOTS/27-bluesteel-fullscreen-button.png" \
    && echo "# screenshot: screenshots/27-bluesteel-fullscreen-button.png"

echo "== reload (mod+r): a changed config and theme, windows untouched"
before_ids="$(cid termA) $(cid termB) $(cid termC)"
sed -i 's/^master_ratio = .*/master_ratio = 0.7/; s/^workspaces = \["main", "web", "code", "chat", "media"\]/workspaces = ["home", "web", "code", "chat", "media", "extra"]/' "$CFG"
eq "before: 5 workspace buttons" 5 "$(nbtn)"
reload
eq "after: 6 workspace buttons" 6 "$(nbtn)"
eq "the same windows (ids) are still managed" "$before_ids" "$(cid termA) $(cid termB) $(cid termC)"
eq "termC (master) is now 70% wide: 0.7 of the work area" "684 706" "$(geo termC | awk '{print $3, $4}')"
eq "'main' was renamed: toolbar shows the new name, same workspace" main "$(curws)"
key super+Tab; key super+shift+Tab
eq "workspace 1 is now called 'home'" home "$(curws)"
check "reload is logged" grep -q "reloaded " "$LOG"
# a keybinding added to the file works after the reload
sed -i 's/^"Mod+m" = "collapse".*/"Mod+x" = "collapse"/' "$CFG"
reload
key super+x
eq "new binding: mod+x rolls the focused window up" 20 "$(fgeo termC | awk '{print $4}')"
key super+m
eq "old binding mod+m is gone (nothing changed)" 20 "$(fgeo termC | awk '{print $4}')"
key super+shift+m
eq "unrolled again" "684 706" "$(geo termC | awk '{print $3, $4}')"
# a broken config is refused and the old one stays
cp "$CFG" "$TMP/config.v2"
printf '[general\nmod = oops\n' >"$CFG"
reload
check "parse error is logged" grep -q "reload: .*keeping the current configuration" "$LOG"
eq "layout untouched by the failed reload" "684 706" "$(geo termC | awk '{print $3, $4}')"
eq "still 6 workspaces" 6 "$(nbtn)"
key super+Tab; eq "keys still work" web "$(curws)"; key super+shift+Tab
sed -i 's/^master_ratio = .*/master_ratio = 2.5/' "$TMP/config.v2"; cp "$TMP/config.v2" "$CFG"
reload
eq "an out-of-range value is refused too (ratio stays 0.7)" "684 706" "$(geo termC | awk '{print $3, $4}')"
# the theme: switch to the default theme, then back
cp "$TMP/config.good" "$CFG"; sed -i "s#^theme = .*#theme = \"$ROOT/themes/default/theme.toml\"#" "$CFG"
reload
eq "default theme: 3px borders (frame is 3px bigger on each side)" "3 3" "$(read -r a b c d <<<"$(geo termC)"; read -r e f g h <<<"$(fgeo termC)"; echo $((a - e)) $((b - f)))"
eq "windows untouched, same ids" "$before_ids" "$(cid termA) $(cid termB) $(cid termC)"
cp "$TMP/config.good" "$CFG"; sed -i "s#^theme = .*#theme = \"$ROOT/themes/bluesteel/theme.toml\"#" "$CFG"
reload
eq "back to Blue Steel: 20px title bar again (L10 T20)" "10 20" "$(read -r a b c d <<<"$(geo termC)"; read -r e f g h <<<"$(fgeo termC)"; echo $((a - e)) $((b - f)))"
eq "and the config's default ratio" "533 706" "$(geo termC | awk '{print $3, $4}')"
eq "5 workspaces again" 5 "$(nbtn)"
check "no window was lost or re-managed by reloading" test "$(grep -c 'managing window' "$LOG")" = 3

echo "== restart (mod+Shift+r): same process, windows kept in place"
# main: termA, termC. web: termD (master) and termB (rolled up). code: termE, fullscreen.
key super+2; launch_term termD; await_win termD
key super+Tab; launch_term termE; await_win termE; key super+f; sleep 0.5
key super+Tab; key super+Tab; key super+Tab; key super+Tab      # chat, media, main, web (wraps)
eq "setup: on web" web "$(curws)"
hover termB; key super+m                                        # roll up termB
G_B=$(fgeo termB); G_D=$(geo termD)
key super+1; G_A=$(geo termA); G_C=$(geo termC); key super+2
eq "setup: back on web" web "$(curws)"
IDS="$(cid termA) $(cid termB) $(cid termC) $(cid termD) $(cid termE)"
FDS=$(ls /proc/$WMPID/fd | wc -l)
key super+shift+r; sleep 2.5
check "same process (re-exec keeps the pid)" kill -0 "$WMPID"
check "restart is logged" grep -q "restarting: re-executing" "$LOG"
eq "all five windows are still there (same ids)" "$IDS" "$(cid termA) $(cid termB) $(cid termC) $(cid termD) $(cid termE)"
eq "still on 'web'" web "$(curws)"
eq "termB is still rolled up, where it was" "$G_B" "$(fgeo termB)"
eq "termD keeps its slot and size" "$G_D" "$(geo termD)"
eq "termA (on main) is hidden" IsUnviewable "$(state termA)"
eq "termC (on main) is hidden" IsUnviewable "$(state termC)"
eq "termE (on code) is hidden" IsUnviewable "$(state termE)"
eq "no leaked file descriptors" "$FDS" "$(ls /proc/$WMPID/fd | wc -l)"
key super+1
eq "mod+1: termA is back on main, in its slot" "$G_A" "$(geo termA)"
eq "termC is the master again" "$G_C" "$(geo termC)"
key super+Tab; key super+Tab
eq "mod+Tab works after the restart (code)" code "$(curws)"
eq "the fullscreen termE survived the restart as fullscreen" "0 0 1024 768" "$(geo termE)"
check "and still carries _NET_WM_STATE_FULLSCREEN" test "$(ewmh termE)" = "_NET_WM_STATE_FULLSCREEN"
key super+f
eq "mod+f puts it back into the layout" "16 46 992 706" "$(geo termE)"
key super+shift+r; sleep 2.5
eq "a second restart: same layout" "16 46 992 706" "$(geo termE)"
key super+Tab
eq "keys work after two restarts" chat "$(curws)"
n=$(grep -c 'reloaded ' "$LOG"); reload
eq "mod+r works after the restarts" $((n + 1)) "$(grep -c 'reloaded ' "$LOG")"
check "no window was lost over the restarts" test "$(cid termA)$(cid termB)$(cid termC)$(cid termD)$(cid termE)" = "$(echo $IDS | tr -d ' ')"

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
