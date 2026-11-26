#!/usr/bin/env bash
# Floating windows and focus: dialogs stay above the tiled windows, closing one
# gives focus back to the window that had it, and moving the mouse inside an
# unfocused window focuses it. Exit status 0 = all checks passed.
cd "$(dirname "$0")"; source ./lib.sh
LOG=/tmp/glo55-floating.log
make -C "$ROOT" -s build/glo55 || exit 1
DIALOGS=()
trap 'kill "${DIALOGS[@]}" 2>/dev/null; cleanup' EXIT
start_x 1 1024x700
start_wm

dialog() { python3 "$ROOT/test/dialog.py" "$@" & DIALOGS+=($!); sleep 0.6; }
# frame id of a client by title (decimal)
frame() {
    local id; id=$(xdotool search --name "^$1\$" 2>/dev/null | head -1)
    printf '%d' "$(xwininfo -tree -id "$id" | awk '/Parent window id/{print $4}')"
}
# above A B: is A's frame stacked over B's? (xwininfo lists root's children top first)
above() {
    local a b pa pb list
    a=$(frame "$1"); b=$(frame "$2")
    list=$(xwininfo -root -children | awk '/^ +0x/{print $1}' | while read -r i; do printf '%d\n' "$i"; done)
    pa=$(grep -nx "$a" <<<"$list" | cut -d: -f1); pb=$(grep -nx "$b" <<<"$list" | cut -d: -f1)
    [ "$pa" -lt "$pb" ]
}
# corner TITLE: the pointer to a window's bottom-right corner (clear of centred dialogs)
corner() { local x y w h; read -r x y w h <<<"$(geo "$1")"; pmove $((x + w - 20)) $((y + h - 20)); sleep 0.4; }
jiggle() { xdotool mousemove_relative -- 3 2; sleep 0.2; xdotool mousemove_relative -- -3 -2; sleep 0.4; }

launch_term termA; launch_term termB; launch_term termC   # [C | B, A]

echo "== a dialog stays above the tiled windows"
hover termB
dialog dlg 300 200
eq "the dialog has focus" dlg "$(focused)"
for w in termA termB termC; do check "opened above $w" above dlg $w; done
for w in termA termB termC; do
    corner $w
    eq "hover $w focuses it" $w "$(focused)"
    check "the dialog is still above $w" above dlg $w
done
launch_term termN
check "a new tiled window opens under the dialog" above dlg termN
key super+shift+c; sleep 0.5
hover dlg; key super+shift+c; sleep 0.5

echo "== keyboard focus reaches a tiled window behind a dialog, and stays there"
hover termC; key super+2
launch_term solo; dialog over 400 300
key super+h; key super+j; key super+k; key super+l
hover over; eq "dialog focused" over "$(focused)"
key super+1; key super+2
eq "back on the workspace: the dialog still has focus" over "$(focused)"
check "and is still above" above over solo
key super+shift+c; sleep 0.5
eq "closing it returns to solo" solo "$(focused)"
key super+shift+c; sleep 0.5; key super+1

hover termC; dialog big 620 400
for d in l h; do key super+$d; done
check "keyboard focus on a tile keeps the dialog above" above big termC
hover big; key super+h
eq "focus left lands on the master, its centre under the dialog" termC "$(focused)"
hover big; key super+shift+c; sleep 0.5

echo "== closing a dialog gives focus back"
for w in termA termB termC; do
    corner $w
    dialog back 300 200
    eq "dialog focused" back "$(focused)"
    key super+shift+c; sleep 0.5
    eq "focus returned to $w" $w "$(focused)"
done
# the pointer is on the dialog when it goes, over a window that was not focused before
hover termA; dialog under 500 300
hover under; kill "${DIALOGS[-1]}"; sleep 0.6
eq "focus returned to termA, not to what was under the pointer" termA "$(focused)"
# tiled windows do the same
hover termB; hover termA; launch_term brief
key super+shift+c; sleep 0.5
eq "closing a tiled window returns to termA" termA "$(focused)"

echo "== nested dialogs"
hover termB; dialog outer 500 400; dialog inner 200 100
read -r x y _ _ <<<"$(geo outer)"; pmove $((x + 10)) $((y + 10)); sleep 0.4
eq "hover the outer dialog" outer "$(focused)"
check "hovering it does not bury the inner one" above inner outer
hover inner; key super+shift+c; sleep 0.5
eq "back to the outer dialog" outer "$(focused)"
key super+shift+c; sleep 0.5
eq "and then to termB" termB "$(focused)"

echo "== mouse movement inside an unfocused window focuses it"
corner termC
dialog jig 300 200
eq "the dialog has focus, the pointer is in termC" jig "$(focused)"
sleep 1.2; eq "a still pointer changes nothing" jig "$(focused)"
jiggle; eq "a jiggle focuses termC" termC "$(focused)"
check "with the dialog still above" above jig termC
hover jig; eq "hover the dialog" jig "$(focused)"
# a new tile takes focus while the pointer rests on a dialog that keeps its motion to itself
launch_term late; eq "new tile focused" late "$(focused)"
jiggle; eq "a jiggle focuses the dialog" jig "$(focused)"
key super+shift+c; sleep 0.5
eq "closing the dialog returns to the new tile" late "$(focused)"
key super+shift+c; sleep 0.5

echo "== fullscreen"
hover termB; key super+f
dialog fsdlg 300 200
check "a dialog opens above a fullscreen window" above fsdlg termB
# the pointer was in termB already: only real (XTEST) movement says it moved
xdotool mousemove 40 650; sleep 0.4
eq "hover the fullscreen window" termB "$(focused)"
check "the dialog stays above it" above fsdlg termB
hover fsdlg; eq "hover the dialog again" fsdlg "$(focused)"
key super+shift+c; sleep 0.5
eq "closing it returns to the fullscreen window" termB "$(focused)"
launch_term behind
eq "a new tile opens behind the fullscreen window, which keeps focus" termB "$(focused)"
check "stacked under it" above termB behind
key super+f
dialog again 300 200
check "a window that left fullscreen is under dialogs again" above again termB
key super+shift+c; sleep 0.5

check "no errors in log" bash -c "! grep -q ERROR '$LOG'"
echo "== $PASS passed, $FAIL failed"
exit $((FAIL>0))
