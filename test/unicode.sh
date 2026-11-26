#!/usr/bin/env bash
# Unicode text test: window titles in every encoding (_NET_WM_NAME, Latin-1 and
# COMPOUND_TEXT WM_NAME, invalid UTF-8), title updates, theme text with \u
# escapes / multibyte literals / Unicode workspace names, Noto Sans and the
# BlueSteel Vixar font (ASCII-ish, so it needs per-character font fallback).
# Screenshots: 17-unicode-default.png, 18-unicode-bluesteel.png.
cd "$(dirname "$0")"; source ./lib.sh
command -v python3 >/dev/null || { echo "SKIP: python3 is needed for titleclient.py"; exit 0; }
LOG=/tmp/glo55-unicode.log
HOST_DISPLAY=$DISPLAY
make -C "$ROOT" -s build/glo55 || exit 1
trap 'pkill -f titleclient.py; rm -rf "$TMP"; cleanup' EXIT
TMP=$(mktemp -d /tmp/glo55-uni.XXXXXX)
T='Café — naïve 日本語 Ελληνικά ✓ ★ 🙂'
WS='["主", "Zürich", "★ star", "Ελλάδα", "🙂"]'

# ---- a Noto Sans variant of the default theme with multibyte theme content
ln -s "$ROOT/themes/default/patterns" "$TMP"/
sed -e 's/^font    = "monospace"/font    = "Noto Sans Regular"/' \
    -e 's|^content = "\$title"\(.*\)|content = "★ $title · \\u2605 \\U0001F642 日本語"\1|' "$ROOT/themes/default/theme.toml" >"$TMP/theme.toml"
sed -e 's/^workspaces = \["main".*/workspaces = '"$WS"'/' -e 's#^theme = .*#theme = "theme.toml"#' \
    "$ROOT/test/config-default.toml" >"$TMP/config.toml"
# ... and a BlueSteel variant with Unicode workspace names
sed -e 's/^workspaces = \["main".*/workspaces = '"$WS"'/' -e "s#^theme = .*#theme = \"$ROOT/themes/bluesteel/theme.toml\"#" \
    "$ROOT/test/config-bluesteel.toml" >"$TMP/config-bluesteel.toml"

await_title() { for _ in $(seq 60); do [ -n "$(xdotool search --name "$1" 2>/dev/null | head -1)" ] && return; sleep 0.1; done; }
roll_all() { for _ in 1 2 3 4 5 6; do key super+m; done; }

run_clients() {
    python3 titleclient.py utf8 "$T" &              # _NET_WM_NAME + WM_NAME, UTF-8
    python3 titleclient.py latin1 "Café naïve (latin1)" &   # WM_NAME as STRING
    python3 titleclient.py ctext "$T (ctext)" &     # WM_NAME as COMPOUND_TEXT only
    python3 titleclient.py net "net only: ✓ ★ 🙂" &
    python3 titleclient.py badutf8 "bad bytes" &
    python3 titleclient.py utf8 "before" "after: 日本語 ✓" &   # PropertyNotify update
    sleep 2.5
}

echo "== default theme with Noto Sans, Unicode workspaces and multibyte theme text"
start_x 1 1024x700
export LC_ALL=C.UTF-8
start_wm "$TMP/config.toml"
run_clients
check "UTF-8 title read intact"           grep -qF "\"$T\" on monitor" "$LOG"
check "Latin-1 WM_NAME converted"         grep -qF '"Café naïve (latin1)" on monitor' "$LOG"
check "COMPOUND_TEXT WM_NAME converted"   grep -qF "\"$T (ctext)\" on monitor" "$LOG"
check "_NET_WM_NAME alone is used"        grep -qF '"net only: ✓ ★ 🙂" on monitor' "$LOG"
check "invalid UTF-8 is repaired (U+FFFD)" grep -qF '"bad bytes ��' "$LOG"
check "a title change is picked up"       grep -qF 'retitled "after: 日本語 ✓"' "$LOG"
check "Noto Sans Regular resolved to Noto Sans" grep -q 'font "Noto Sans:style=Regular:pixelsize=1[0-9]" opened as family "Noto Sans"' "$LOG"
check "CJK falls back to a CJK font"      grep -q 'fallback for U+[0-9A-F]*: font family "Noto Sans CJK' "$LOG"
check "emoji finds a font"                grep -q 'fallback for U+1F642: font family' "$LOG"
check "no log.error / X protocol errors"  bash -c "! grep -E 'ERROR|BadLength|BadMatch|BadAlloc|BadFont|RenderBad' '$LOG'"
roll_all; sleep 0.3
shot 17-unicode-default.png
check "window manager still running"      kill -0 "$WMPID"
pkill -f titleclient.py; kill "$WMPID"; wait "$WMPID" 2>/dev/null
kill "$XPID"; wait "$XPID" 2>/dev/null

export DISPLAY=$HOST_DISPLAY; LOG=/tmp/glo55-unicode-bluesteel.log
echo "== BlueSteel (Vixar font has no CJK/emoji glyphs: needs fallback)"
start_x 1 1024x768
start_wm "$TMP/config-bluesteel.toml"
run_clients
check "Vixar: CJK falls back to a CJK font" grep -q 'fallback for U+[0-9A-F]*: font family "Noto Sans CJK' "$LOG"
check "Vixar: Greek falls back to a font with it" grep -q 'fallback for U+03AC: font family' "$LOG"
check "BlueSteel: no log.error / X protocol errors" bash -c "! grep -E 'ERROR|BadLength|BadMatch|BadAlloc|BadFont|RenderBad' '$LOG'"
roll_all; sleep 0.3
shot 18-unicode-bluesteel.png
check "window manager still running"      kill -0 "$WMPID"

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
