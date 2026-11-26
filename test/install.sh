#!/usr/bin/env bash
# make install / uninstall into a staging directory (PREFIX=/usr, DESTDIR=...),
# then the *staged* binary run from an unrelated directory with an empty HOME:
# it must find the installed default config and the bundled themes by itself,
# and a user config in ~/.config/glo55 must override it.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-install.log
TMP=$(mktemp -d)
trap 'cleanup; rm -rf "$TMP"' EXIT
STAGE="$TMP/stage"; mkdir -p "$TMP/home" "$TMP/cwd"

echo "== make install DESTDIR=stage PREFIX=/usr"
make -C "$ROOT" -s install DESTDIR="$STAGE" PREFIX=/usr V="${V:-v}" >/tmp/glo55-install-make.log 2>&1
check "make install succeeds" test -x "$STAGE/usr/bin/glo55"
check "default config installed" test -f "$STAGE/usr/share/glo55/config.toml"
check "default theme installed (with its patterns)" test -f "$STAGE/usr/share/glo55/themes/default/patterns/grid.png" -a -f "$STAGE/usr/share/glo55/themes/default/theme.toml"
check "Blue Steel installed with its art, font and licence" test -f "$STAGE/usr/share/glo55/themes/bluesteel/theme.toml" -a -f "$STAGE/usr/share/glo55/themes/bluesteel/borders/DEFAULT/images/maximize_fg.png" -a -f "$STAGE/usr/share/glo55/themes/bluesteel/ttfonts/vixar.ttf" -a -f "$STAGE/usr/share/glo55/themes/bluesteel/COPYING"
check "Fossils of the Machines installed with its art, font, licence and credits" test -f "$STAGE/usr/share/glo55/themes/fossils/theme.toml" -a -f "$STAGE/usr/share/glo55/themes/fossils/artwork/borders/frame_active.png" -a -f "$STAGE/usr/share/glo55/themes/fossils/glo55/fullscreen.png" -a -f "$STAGE/usr/share/glo55/themes/fossils/ttfonts/Satis.ttf" -a -f "$STAGE/usr/share/glo55/themes/fossils/ABOUT/README" -a -f "$STAGE/usr/share/glo55/themes/fossils/README.md"
check "CORPO installed with its art, fonts, generated parts and README" test -f "$STAGE/usr/share/glo55/themes/corpo/theme.toml" -a -f "$STAGE/usr/share/glo55/themes/corpo/assets/win-barleft.png" -a -f "$STAGE/usr/share/glo55/themes/corpo/assets/bg-ruins.gif" -a -f "$STAGE/usr/share/glo55/themes/corpo/glo55/active/btn-fullscreen.png" -a -f "$STAGE/usr/share/glo55/themes/corpo/glo55/inactive/win-bartile.png" -a -f "$STAGE/usr/share/glo55/themes/corpo/fonts/pixeltimes.ttf" -a -f "$STAGE/usr/share/glo55/themes/corpo/README.md"
check "Fresh Breath installed: shared layout, fonts + licence, and all four palettes with their art" test -f "$STAGE/usr/share/glo55/themes/fresh-breath/layout.toml" -a -f "$STAGE/usr/share/glo55/themes/fresh-breath/fonts/BarlowCondensed-SemiBoldItalic.ttf" -a -f "$STAGE/usr/share/glo55/themes/fresh-breath/fonts/Barlow-Medium.ttf" -a -f "$STAGE/usr/share/glo55/themes/fresh-breath/fonts/OFL.txt" -a -f "$STAGE/usr/share/glo55/themes/fresh-breath/README.md" -a -f "$STAGE/usr/share/glo55/themes/fresh-breath/sedona/theme.toml" -a -f "$STAGE/usr/share/glo55/themes/fresh-breath/painted-desert/art/active/title.png" -a -f "$STAGE/usr/share/glo55/themes/fresh-breath/chillwave/art/inactive/buttons.png" -a -f "$STAGE/usr/share/glo55/themes/fresh-breath/office-print/art/desktop.png"
check "geo55 installed with its art, font, licence and README" test -f "$STAGE/usr/share/glo55/themes/geo55/theme.toml" -a -f "$STAGE/usr/share/glo55/themes/geo55/art/frame.png" -a -f "$STAGE/usr/share/glo55/themes/geo55/art/band.png" -a -f "$STAGE/usr/share/glo55/themes/geo55/fonts/W95FA.otf" -a -f "$STAGE/usr/share/glo55/themes/geo55/fonts/OFL.txt" -a -f "$STAGE/usr/share/glo55/themes/geo55/README.md"
check "X session entry installed, Exec points at PREFIX" grep -qx "Exec=/usr/bin/glo55" "$STAGE/usr/share/xsessions/glo55.desktop"
check "installed config uses Blue Steel by name" grep -qx 'theme = "bluesteel/theme.toml"' "$STAGE/usr/share/glo55/config.toml"
check "nothing outside DESTDIR was written" test ! -e /usr/share/glo55
check "the binary has no dev leftovers beside it" test "$(ls "$STAGE/usr/bin")" = glo55

BIN="$STAGE/usr/bin/glo55"
runwm() { # runwm [env assignments...]: the staged binary, unrelated cwd, our own HOME, no config in sight
    pushd "$TMP/cwd" >/dev/null
    env -u GLO55_CONFIG -u GLO55_DATADIR -u XDG_CONFIG_HOME HOME="$TMP/home" GLO55_DEBUG=1 PATH=/tmp/glo55-fakebin "$@" "$BIN" >"$LOG" 2>&1 &
    echo $! >"$TMP/pid"; popd >/dev/null
    WMPID=$(cat "$TMP/pid"); sleep 1.2; }
stopwm() { kill "$WMPID" 2>/dev/null; wait "$WMPID" 2>/dev/null; sleep 0.3; }
await_win() { for _ in $(seq 60); do [ "$(state "$1")" = IsViewable ] && return; sleep 0.1; done; }
mkdir -p /tmp/glo55-fakebin; for b in xterm sh; do ln -sf "$(command -v $b)" /tmp/glo55-fakebin/$b; done

start_x 1 1024x768

echo "== the staged binary, no config anywhere but the installed one"
runwm
check "it runs" kill -0 "$WMPID"
check "loaded the installed default config" grep -q "loaded config $STAGE/usr/share/glo55/config.toml" "$LOG"
check "...and Blue Steel from the installed themes" grep -q "loaded theme $STAGE/usr/share/glo55/themes/bluesteel/theme.toml" "$LOG"
launch_term termA; await_win termA
eq "Blue Steel geometry (title bar insets) from a cwd with no config" "16 46 992 706" "$(geo termA)"
stopwm; pkill -f "xterm -T term" 2>/dev/null

echo "== the installed Fossils theme, from a config that names it"
sed 's|^theme = .*|theme = "fossils/theme.toml"|' "$ROOT/config.toml" >"$TMP/fossils.toml"
runwm GLO55_CONFIG="$TMP/fossils.toml"
check "loaded the temp config" grep -q "loaded config $TMP/fossils.toml" "$LOG"
check "...and the Fossils theme from the installed themes" grep -q "loaded theme $STAGE/usr/share/glo55/themes/fossils/theme.toml" "$LOG"
check "its bundled font was registered" grep -q 'font "Dissatisfaction' "$LOG"
check "no image failed to load" test -z "$(grep 'cannot load image' "$LOG")"
launch_term termA; await_win termA
eq "Fossils geometry (insets 18/16/1/4, toolbar 16) from a cwd with no config" "24 38 993 720" "$(geo termA)"
stopwm; pkill -f "xterm -T term" 2>/dev/null

echo "== the installed CORPO theme, from a config that names it"
sed 's|^theme = .*|theme = "corpo/theme.toml"|' "$ROOT/config.toml" >"$TMP/corpo.toml"
runwm GLO55_CONFIG="$TMP/corpo.toml"
check "loaded the temp config and the CORPO theme" grep -q "loaded theme $STAGE/usr/share/glo55/themes/corpo/theme.toml" "$LOG"
check "both bundled fonts were registered" test "$(grep -c 'font "Pixel Times\|font "RoundedSquare' "$LOG")" -ge 2
check "no image failed to load" test -z "$(grep 'cannot load image' "$LOG")"
launch_term termA; await_win termA
eq "CORPO geometry (insets 3/25/3/3, toolbar 30) from a cwd with no config" "9 61 1006 698" "$(geo termA)"
stopwm; pkill -f "xterm -T term" 2>/dev/null

echo "== the installed Fresh Breath theme, from a config that names a palette"
sed 's|^theme = .*|theme = "fresh-breath/chillwave/theme.toml"|' "$ROOT/config.toml" >"$TMP/fresh-breath.toml"
runwm GLO55_CONFIG="$TMP/fresh-breath.toml"
check "loaded the temp config and the palette's theme" grep -q "loaded theme $STAGE/usr/share/glo55/themes/fresh-breath/chillwave/theme.toml" "$LOG"
check "its bundled Barlow Condensed font was registered" grep -q 'font "Barlow Condensed' "$LOG"
check "no image failed to load (layout from ../layout.toml, art from the palette)" test -z "$(grep 'cannot load image' "$LOG")"
launch_term termA; await_win termA
eq "Fresh Breath geometry (insets 9/38/5/5, toolbar 30) from a cwd with no config" "19 78 990 675" "$(geo termA)"
stopwm; pkill -f "xterm -T term" 2>/dev/null

echo "== the installed geo55 theme, from a config that names it"
sed 's|^theme = .*|theme = "geo55/theme.toml"|' "$ROOT/config.toml" >"$TMP/geo55.toml"
runwm GLO55_CONFIG="$TMP/geo55.toml"
check "loaded the temp config and the geo55 theme" grep -q "loaded theme $STAGE/usr/share/glo55/themes/geo55/theme.toml" "$LOG"
check "its bundled W95FA font was registered" grep -q 'font "W95FA' "$LOG"
check "no image failed to load" test -z "$(grep 'cannot load image' "$LOG")"
launch_term termA; await_win termA
# NOTE: geometry was rebaselined for the two-band geo55 theme (insets 3/29/4/4,
# gap 4, both bands in one 30px row); re-check on a real display.
eq "geo55 geometry (insets 3/29/4/4, toolbar row 30) from a cwd with no config" "7 63 1009 697" "$(geo termA)"
stopwm; pkill -f "xterm -T term" 2>/dev/null

echo "== a user config in ~/.config/glo55 overrides the installed one"
mkdir -p "$TMP/home/.config/glo55"
cat >"$TMP/home/.config/glo55/config.toml" <<'EOC'
[general]
theme = "default/theme.toml"
[layout]
master_ratio = 0.6
[[monitors]]
workspaces = ["alpha", "beta"]
[keybindings]
"Mod+q" = "quit"
EOC
runwm
check "the user's config wins" grep -q "loaded config $TMP/home/.config/glo55/config.toml" "$LOG"
check "its theme name is found in the installed themes" grep -q "loaded theme $STAGE/usr/share/glo55/themes/default/theme.toml" "$LOG"
launch_term termA; await_win termA
read -r x y w h <<<"$(geo termA)"; read -r fx fy fw fh <<<"$(fgeo termA)"
eq "default theme: 3px borders" "3 3" "$((x - fx)) $((y - fy))"
stopwm; pkill -f "xterm -T term" 2>/dev/null

echo "== ~/.config/glo55/themes/ is searched before the installed themes"
mkdir -p "$TMP/home/.config/glo55/themes/bluesteel"
cp "$ROOT/themes/bluesteel/theme.toml" "$TMP/home/.config/glo55/themes/bluesteel/theme.toml"
sed -i 's|theme = .*|theme = "bluesteel/theme.toml"|' "$TMP/home/.config/glo55/config.toml"
runwm
check "~/.config/glo55/themes/ is searched before the installed themes" grep -q "loaded theme $TMP/home/.config/glo55/themes/bluesteel/theme.toml" "$LOG"
stopwm
sed -i 's|theme = .*|theme = "themes/bluesteel/theme.toml"|' "$TMP/home/.config/glo55/config.toml"
rm -rf "$TMP/home/.config/glo55/themes"
runwm
check "the source-tree spelling themes/NAME/theme.toml works too" grep -q "loaded theme $STAGE/usr/share/glo55/themes/bluesteel/theme.toml" "$LOG"
stopwm

echo "== -c, \$GLO55_CONFIG and \$GLO55_DATADIR"
rm -rf "$TMP/home/.config"
mv "$STAGE/usr/share/glo55" "$TMP/moved-data"    # no longer next to the binary
BIN="$STAGE/usr/bin/glo55"
runwm
check "no installed config reachable: falls back to ./config.toml (and says it cannot read it)" grep -q "config: cannot read config.toml" "$LOG"
runwm GLO55_DATADIR="$TMP/moved-data"
check "GLO55_DATADIR finds the config" grep -q "loaded config $TMP/moved-data/config.toml" "$LOG"
check "and the theme" grep -q "loaded theme $TMP/moved-data/themes/bluesteel/theme.toml" "$LOG"
stopwm
mv "$TMP/moved-data" "$STAGE/usr/share/glo55"

echo "== make uninstall"
make -C "$ROOT" -s uninstall DESTDIR="$STAGE" PREFIX=/usr
check "binary, data and session entry are gone" test ! -e "$STAGE/usr/bin/glo55" -a ! -e "$STAGE/usr/share/glo55" -a ! -e "$STAGE/usr/share/xsessions/glo55.desktop"

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
