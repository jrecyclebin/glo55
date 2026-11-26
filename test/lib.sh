# Shared helpers for the functional tests (sourced by functional.sh / multimonitor.sh).
# Starts a nested X server (Xephyr if a host X is available, else Xvfb), runs
# glo55 in it and offers tiny assertion helpers built on xdotool/xwininfo.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
D="${NESTED_DISPLAY:-:9}"
PASS=0; FAIL=0
SHOTS="$ROOT/screenshots"; mkdir -p "$SHOTS"

start_x() {            # start_x MONITORS SIZE
    local n="$1" size="$2" screens=() i
    # a previous server on this display may still be shutting down
    for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X${D#:}" ] || break; sleep 0.1; done
    for i in $(seq "$n"); do screens+=(-screen "$size"); done
    if [ -z "${HEADLESS:-}" ] && [ -n "${DISPLAY:-}" ] && xdpyinfo >/dev/null 2>&1; then
        echo "# X server: Xephyr $D on host $DISPLAY, $n screen(s) $size"
        Xephyr "$D" "${screens[@]}" +xinerama -ac -br -noreset >/dev/null 2>&1 &
        # keep the *host* pointer off Xephyr's own windows: while it hovers
        # over one, Xephyr re-slaves the nested pointer to that screen and even
        # real warps clamp to it. Park it in a corner until the run is over.
        # xdotool (XTEST) is fine on the single-screen host: this parks the HOST pointer
        xdotool mousemove --screen 0 $(xdpyinfo | awk '/dimensions:/ {
            split($2, a, "x"); print a[1] - 40, a[2] - 40}')
    else
        echo "# X server: Xvfb $D (headless), $n screen(s) $size"
        local vs=(); for i in $(seq 0 $((n-1))); do vs+=(-screen "$i" "${size}x24"); done
        Xvfb "$D" "${vs[@]}" +xinerama -ac -noreset >/dev/null 2>&1 &
    fi
    XPID=$!
    for _ in $(seq 100); do DISPLAY="$D" xdpyinfo >/dev/null 2>&1 && break; sleep 0.1; done
    export DISPLAY="$D"
}

# start_wm CONFIG [extra env assignments are taken from the caller's environment]
start_wm() {
    # restricted PATH: no kitty, so the "exec kitty" binding must fall back to xterm
    mkdir -p /tmp/glo55-fakebin
    for b in xterm sh; do ln -sf "$(command -v $b)" /tmp/glo55-fakebin/$b; done
    GLO55_DEBUG=1 PATH=/tmp/glo55-fakebin "$ROOT/build/glo55" -c "${1:-$ROOT/test/config-default.toml}" >"$LOG" 2>&1 &
    WMPID=$!
    sleep 1.2
}

cleanup() {
    kill "$WMPID" 2>/dev/null; pkill -f "xterm -T term" 2>/dev/null; pkill xeyes 2>/dev/null
    pkill xclock 2>/dev/null; kill "$XPID" 2>/dev/null; wait "$XPID" 2>/dev/null; true
}

ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
check(){ local desc="$1"; shift; if "$@"; then ok "$desc"; else bad "$desc"; fi; }
eq()   { # eq DESC EXPECTED ACTUAL
    if [ "$2" = "$3" ]; then ok "$1 (= $3)"; else bad "$1: expected '$2' got '$3'"; fi; }

wid()  { xdotool search --onlyvisible --name "^$1\$" 2>/dev/null | head -1; }
# pmove X Y: place the pointer at root coordinates. NOT xdotool mousemove:
# that goes through XTEST, which Xephyr confines to the screen the pointer is
# on, so cross-monitor moves clamp at the Xinerama boundary (warp.py explains).
pmove() { python3 "$ROOT/test/warp.py" "$1" "$2"; }
# nudge: a 1px round trip through XTEST, which (unlike a warp) is real mouse
# movement to the WM: it focuses the window under the pointer even when the
# pointer was already inside it.
nudge() { xdotool mousemove_relative -- 1 0 mousemove_relative -- -1 0; }
# geometry of a client by title: "x y w h" in root coordinates
geo()  {
    local id; id=$(xdotool search --name "^$1\$" 2>/dev/null | head -1)
    [ -z "$id" ] && { echo "none"; return; }
    # (xdotool's own position is off for reparented windows; xwininfo is exact)
    xwininfo -id "$id" | awk '/Absolute upper-left X/{x=$4}/Absolute upper-left Y/{y=$4}/Width:/{w=$2}/Height:/{h=$2}END{print x,y,w,h}'
}
# frame geometry of a client by title: "x y w h" (the parent frame window)
fgeo() {
    local id par; id=$(xdotool search --name "^$1\$" 2>/dev/null | head -1)
    [ -z "$id" ] && { echo "none"; return; }
    par=$(xwininfo -tree -id "$id" | awk '/Parent window id/{print $4}')
    xwininfo -id "$par" | awk '/Absolute upper-left X/{x=$4}/Absolute upper-left Y/{y=$4}/Width:/{w=$2}/Height:/{h=$2}END{print x,y,w,h}'
}
# hover_bar TITLE: move the pointer onto the centre of a window's *frame* (works for rolled-up bars)
hover_bar() { read -r x y w h <<<"$(fgeo "$1")"; pmove $((x + w/2)) $((y + h/2)); nudge; sleep 0.4; }
state(){ # map state of a client by title: IsViewable / IsUnviewable / IsUnMapped / none
    local id; id=$(xdotool search --name "^$1\$" 2>/dev/null | head -1)
    [ -z "$id" ] && { echo none; return; }
    xwininfo -id "$id" | awk '/Map State/{print $3}'; }
focused() { xdotool getwindowfocus getwindowname 2>/dev/null; }
key()  { xdotool key --delay 80 "$@"; sleep 0.45; }
hover(){ # hover TITLE: move the pointer to the centre of a window
    read -r x y w h <<<"$(geo "$1")"; pmove $((x + w/2)) $((y + h/2)); nudge; sleep 0.4; }
shot() { import -window root "$SHOTS/$1" && echo "# screenshot: screenshots/$1"; }
launch_term() {
    xterm -T "$1" -geometry 40x10 -fa 'DejaVu Sans Mono' -fs 11 -bg '#1a1b26' -fg '#c0caf5' \
        -e sh -c "printf 'glo55 test terminal: %s\n\n' '$1'; ls --color=always /workspace/glo55 | head -20; sleep 3000" &
    sleep 0.6
}
