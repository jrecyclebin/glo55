#!/usr/bin/env bash
# Multiple toolbars pinned to one monitor: flow-wrapped painting, reserved row
# height, independent workspace-button routing, and reload creating/removing bars.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-multiple-toolbars.log
make -C "$ROOT" -s build/glo55 || exit 1
trap 'cleanup; rm -rf "$TMP"' EXIT
TMP=$(mktemp -d)

cat >"$TMP/config.toml" <<EOF
[general]
theme = "$TMP/theme.toml"
time_format = "HH:mm:ss"

[layout]
master_ratio = 0.55

[[monitors]]
workspaces = ["main", "web", "code"]

[keybindings]
"Mod+1" = "workspace 1"
"Mod+Shift+q" = "quit"
"Mod+r" = "reload"
EOF

cat >"$TMP/windows.toml" <<'EOF'
[[windows]]
border_width = 2
window_gap = 4

[windows.background]
type = "solid"
fore = "#404040"
EOF

cat >"$TMP/first-toolbar.toml" <<'EOF'
[[toolbars]]
monitor = 0
height = 24
width = 200
align = "left"

[toolbars.face]
type = "solid"
fore = "#aa0000"
EOF

cat >"$TMP/second-toolbar.toml" <<'EOF'
[[toolbars]]
monitor = 0
height = 18
width = 200
align = "right"

[toolbars.face]
type = "solid"
fore = "#0000aa"

[toolbars.workspace_buttons]
left = { edge = "left", offset = 8 }
top = { edge = "top", offset = 2 }
right = { edge = "left", offset = 300 }
bottom = { edge = "bottom", offset = -2 }
spacing = 2
padding = 8
min_width = 30

[toolbars.workspace_buttons.label]
type = "text"
content = "$workspace"
font = "monospace"
size = 12
fore = "#ffffff"
align = "center"
EOF

cat "$TMP/windows.toml" "$TMP/first-toolbar.toml" "$TMP/second-toolbar.toml" >"$TMP/two-toolbars.toml"
cat "$TMP/windows.toml" "$TMP/first-toolbar.toml" >"$TMP/one-toolbar.toml"
cp "$TMP/two-toolbars.toml" "$TMP/theme.toml"

await_win() { for _ in $(seq 60); do [ "$(state "$1")" = IsViewable ] && return; sleep 0.1; done; }
await_geo() { for _ in $(seq 60); do [ "$(geo "$2")" = "$1" ] && return; sleep 0.1; done; }
button() {
    grep 'monitor 0 toolbar 1 workspace buttons:' "$LOG" | tail -1 | sed 's/.*buttons: //' | \
        cut -d, -f"$(( $1 + 1 ))"
}
px() { convert "$1" -depth 8 -format "%[fx:int(255*p{$2,$3}.r+0.5)] %[fx:int(255*p{$2,$3}.g+0.5)] %[fx:int(255*p{$2,$3}.b+0.5)]" info:; }

start_x 1 800x600
start_wm "$TMP/config.toml"

echo "== two pinned toolbars share the first row when they fit"
check "the left bar occupies the upper-left corner" grep -q 'monitor 0 toolbar rect: 0:0:200:24' "$LOG"
check "the right bar occupies the upper-right corner" grep -q 'monitor 0 toolbar 1 rect: 600:0:200:18' "$LOG"
import -window root "$TMP/bars.png"
check "the left bar is painted red" test "$(px "$TMP/bars.png" 50 10)" = '170 0 0'
check "the right bar is painted blue" test "$(px "$TMP/bars.png" 700 10)" = '0 0 170'

launch_term termA; await_win termA
eq "only the shared row's tallest height is reserved" "6 30 788 564" "$(geo termA)"

echo "== workspace buttons on the right bar receive their own clicks"
read -r bx by bw bh <<<"$(button 1 | tr : ' ')"
check "the right bar laid out its workspace buttons" test -n "$bx"
pmove $((600 + bx + bw / 2)) $((by + bh / 2)); sleep 0.2
xdotool click 1; sleep 0.6
check "clicking the right bar switches to web" grep -q 'monitor 0: workspace "web"' "$LOG"
key super+1 # make termA's workspace visible before checking its layout

echo "== reload removes and recreates toolbar windows"
cp "$TMP/one-toolbar.toml" "$TMP/theme.toml"
key super+r
await_geo "6 30 788 564" termA
eq "removing the right bar leaves the remaining row height" "6 30 788 564" "$(geo termA)"
cp "$TMP/two-toolbars.toml" "$TMP/theme.toml"
key super+r
await_geo "6 30 788 564" termA
eq "restoring the second bar keeps one shared row" "6 30 788 564" "$(geo termA)"
check "the recreated right bar is mapped and painted" grep -q 'monitor 0 toolbar 1 rect: 600:0:200:18' "$LOG"
check "no runtime X errors" test -z "$(grep 'X error:' "$LOG")"

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
