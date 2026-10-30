#!/bin/bash
# End to end on real macOS with throwaway windows only. Opens mielwm-testwindows
# windows, runs `mielwm --manage-only <their pid>` (no shortcuts, never takes
# focus) with its own socket and settings, and drives it over its socket the
# way you would from the command line. Two test copies run in turn:
#
#   floating  pan away so the windows park, pan back so they return, let the
#             app move a window and check the canvas adopted it, quit, and
#             check every window is back on screen.
#   tiles     adopt the windows on workspaces, switch workspaces, focus a
#             window, move it to another workspace, stack, tile and float,
#             close and minimize, open, search and close the overview (drawn,
#             with MIELWM_TEST_OVERLAY), rescan, answer the `aerospace`
#             command, quit, and check the test copy left nothing behind.
#
# Exits non-zero on the first failed check. Never touches other windows.
# Puts windows and an overlay on screen: run it while nobody uses the Mac,
# as scripts/e2e.sh does.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build >/dev/null 2>&1 || { swift build; exit 1; }
BIN=.build/debug/mielwm
HELPER=.build/debug/mielwm-testwindows
AEROSPACE=.build/debug/mielwm-aerospace
work=$(mktemp -d "${TMPDIR:-/tmp}/mielwm-system-test.XXXXXX")
export MIELWM_SOCKET="$work/s.sock"
# Its own settings, never yours.
export MIELWM_CONFIG_DIR="$work/config"
mkdir -p "$MIELWM_CONFIG_DIR"

helper_pid="" app_pid=""
stop_all() {
    if [ -n "$app_pid" ]; then kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; fi
    if [ -n "$helper_pid" ]; then kill "$helper_pid" 2>/dev/null || true; fi
    app_pid="" helper_pid=""
}
cleanup() {
    stop_all
    rm -rf "$work"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    [ -n "$app_pid" ] && "$BIN" state >&2 2>/dev/null || true # what the test copy saw, for the report
    exit 1
}
step() { echo "== $*"; }

# Prints the value of a Python expression over `mielwm state` (as `s`).
state() { "$BIN" state | python3 -I -c "import json,sys; s=json.load(sys.stdin); print($1)"; }
# Prints the value of a Python expression over the helper's windows from --list-windows (as `w`, by title).
windows() {
    "$BIN" --list-windows --json --pid "$helper_pid" | python3 -I -c "
import json,sys
w={x['title']: x for x in json.load(sys.stdin)}
print($1)"
}
# The canvas's window titled $1, as a Python expression over `s`.
win() { echo "[x for x in s['windows'] if x['title']=='$1'][0]"; }
# Waits up to $2 seconds (default 5) until the Python expression $1 over `mielwm state` is True.
until_state() {
    local deadline=$((SECONDS + ${2:-5}))
    until [ "$(state "$1" 2>/dev/null)" = True ]; do
        [ $SECONDS -ge $deadline ] && return 1
        sleep 0.1
    done
}
# The same over --list-windows.
until_windows() {
    local deadline=$((SECONDS + ${2:-5}))
    until [ "$(windows "$1" 2>/dev/null)" = True ]; do
        [ $SECONDS -ge $deadline ] && return 1
        sleep 0.1
    done
}
# Nothing flies, and macOS has confirmed every move Core sent.
settled() { until_state "s['settled']" "${1:-5}"; }

# Opens test windows at the given frames and starts a test copy managing only them.
launch() {
    exec 3< <(exec "$HELPER" --frames "$1" 2>/dev/null)
    read -r helper_pid <&3
    "$BIN" --manage-only "$helper_pid" 2>/dev/null &
    app_pid=$!
    until_state "len(s['windows']) == $2" 10 || fail "the canvas did not pick up the $2 test windows"
}

# Quits the test copy: it must exit, and every window must be back on screen.
quit_and_check() {
    "$BIN" quit >/dev/null
    local deadline=$((SECONDS + 5))
    while kill -0 "$app_pid" 2>/dev/null; do
        [ $SECONDS -ge $deadline ] && fail "the app did not quit"
        sleep 0.1
    done
    wait "$app_pid" 2>/dev/null || true
    [ -d "${TMPDIR:-/tmp}/mielwm-manage-only-$app_pid" ] && fail "the test copy left its scratch folder behind"
    app_pid=""
    until_windows "all(x['visible'] or x['minimized'] for x in w.values())" || fail "after quit: $(windows 'w')"
}

# --- Floating windows: panning parks them and brings them back.

step "floating: mielwm --manage-only adopts two test windows"
echo '{"layout:default": "floating"}' > "$MIELWM_CONFIG_DIR/config.json"
launch "200,200,480,320;760,260,480,320" 2
start=$(windows 'w["PT-1"]["frame"]')

pan() { for _ in 1 2 3 4 5; do "$BIN" pan "$1" >/dev/null; done; }

step "floating: pan right until the windows leave the screen: they park"
pan right
until_state "all(x['parked'] for x in s['windows'])" || fail "not parked: $(state 's["windows"]')"
until_windows "not any(x['visible'] for x in w.values())" || fail "a parked window is still on screen"

step "floating: pan back: they return where they were"
pan left
until_state "not any(x['parked'] for x in s['windows'])" || fail "still parked after panning back"
until_windows "w['PT-1']['frame'] == $start" || fail "PT-1 came back at $(windows 'w["PT-1"]["frame"]'), not $start"

step "floating: the app moves PT-1 by itself: the canvas adopts the move"
before=$(state "$(win PT-1)['frame']")
kill -USR1 "$helper_pid"
moved=$(python3 -I -c "b=$before; print([b[0]+100, b[1]+60, b[2], b[3]])")
until_state "$(win PT-1)['frame'] == $moved" || fail "canvas frame $(state "$(win PT-1)['frame']"), expected $moved"

step "floating: park again, then quit: every window back on screen"
pan right
until_state "all(x['parked'] for x in s['windows'])" || fail "not parked before quit"
quit_and_check
stop_all

# --- Tiles: workspaces, layouts and the overview.

step "tiles: two windows open before mielwm: each gets a workspace"
echo '{"layout:default": "tiles", "animation:enabled": false}' > "$MIELWM_CONFIG_DIR/config.json"
export MIELWM_TEST_OVERLAY=1
launch "200,200,480,320;760,260,480,320" 2
until_state "sorted(x.get('workspace') for x in s['windows']) == [1, 2]" || fail "workspaces: $(state 's["workspaces"]')"
settled || fail "the tiles did not settle: $(state 's["windows"]')"
first=$(state "[x['title'] for x in s['windows'] if x.get('workspace') == s.get('workspace')][0]")
other=$([ "$first" = PT-1 ] && echo PT-2 || echo PT-1)
other_ws=$(state "$(win "$other").get('workspace')")

step "tiles: switch to the other workspace: its window shows, the first one parks"
"$BIN" workspace "$other_ws" >/dev/null
until_state "s.get('workspace') == $other_ws and $(win "$first")['parked'] and not $(win "$other")['parked']" \
    || fail "after workspace $other_ws: $(state 's["windows"]')"
until_windows "w['$other']['visible'] and not w['$first']['visible']" || fail "on screen: $(windows 'w')"

step "tiles: the aerospace command lists both workspaces and switches back"
listed=$("$AEROSPACE" list-workspaces --all --json)
[ "$(echo "$listed" | python3 -I -c 'import json,sys; print(sorted(int(x["workspace"]) for x in json.load(sys.stdin)))')" = "[1, 2]" ] \
    || fail "aerospace list-workspaces printed $listed"
first_ws=$(state "$(win "$first").get('workspace')")
"$AEROSPACE" workspace "$first_ws"
until_state "s.get('workspace') == $first_ws and not $(win "$first")['parked']" || fail "aerospace workspace $first_ws did nothing"

step "tiles: focus the other window, then move it to this workspace"
"$AEROSPACE" focus --window-id "$(state "$(win "$other")['number']")" >/dev/null
until_state "s['focused'] == $(win "$other")['id']" || fail "focus did not land on $other"
"$BIN" move-to-workspace "$first_ws" >/dev/null
until_state "all(x.get('workspace') == $first_ws for x in s['windows']) and not any(x['parked'] for x in s['windows'])" \
    || fail "after move-to-workspace: $(state 's["windows"]')"
settled || fail "the tiles did not settle after the move"
until_state "$(win PT-1)['frame'][1] == $(win PT-2)['frame'][1] and $(win PT-1)['frame'][0] != $(win PT-2)['frame'][0]" \
    || fail "not side by side: $(state 's["windows"]')"

step "tiles: stack, then tiles again"
"$BIN" layout stack >/dev/null
until_state "any(x['mode'] == 'stack' for x in s['workspaces'])" || fail "no stack"
settled || fail "the stack did not settle"
"$BIN" layout tiles >/dev/null
until_state "all(x['mode'] == 'tiles' for x in s['workspaces'] if x['members'])" || fail "not tiles again"
settled || fail "the tiles did not settle"

step "tiles: float the focused window, then tile it again"
"$BIN" layout floating >/dev/null
until_state "$(win "$other").get('workspace') is None" || fail "$other did not float"
"$BIN" layout floating >/dev/null
until_state "$(win "$other").get('workspace') == $first_ws" || fail "$other did not join the tiles again"
settled || fail "the tiles did not settle"

step "tiles: focus moves left and right between the tiles"
left=$(state "min(s['windows'], key=lambda x: x['frame'][0])['id']")
right=$(state "max(s['windows'], key=lambda x: x['frame'][0])['id']")
"$BIN" focus right >/dev/null
until_state "s['focused'] == '$right'" || fail "focus right landed on $(state "s['focused']")"
"$BIN" focus left >/dev/null
until_state "s['focused'] == '$left'" || fail "focus left landed on $(state "s['focused']")"

step "tiles: open the overview, search, and close it with back"
drawn=$(state "s['framesDrawn']")
"$BIN" overview >/dev/null
until_state "s['overview']" || fail "the overview did not open"
until_state "s['framesDrawn'] > $drawn" || fail "the overview drew no frames"
"$BIN" search "$other" >/dev/null
until_state "s['selection'] == $(win "$other")['id']" || fail "search did not select $other"
"$BIN" back >/dev/null
until_state "not s['overview']" || fail "back did not close the overview"

step "tiles: after several workspace switches, the overview still draws"
"$BIN" layout floating >/dev/null # the focused window floats, so the other workspace has one to show
# Flights, as you'd see them, and live pictures stopped: they linger 3 s after the overlay
# hides. Nothing reports the streams, so this one waits by the clock.
echo '{"layout:default": "tiles", "animation:enabled": true}' > "$MIELWM_CONFIG_DIR/config.json"
sleep 4
for n in $other_ws $first_ws $other_ws $first_ws $other_ws $first_ws; do "$BIN" workspace "$n" >/dev/null; until_state "s.get('workspace') == $n and s['settled']" || fail "workspace $n"; done
drawn=$(state "s['framesDrawn']")
"$BIN" overview >/dev/null
until_state "s['overview'] and s['framesDrawn'] > $drawn" 3 || fail "the overview drew no frames after workspace switches"
drawn=$(state "s['framesDrawn']")
"$BIN" pan right >/dev/null
until_state "s['framesDrawn'] > $drawn" 3 || fail "the overview stopped drawing while panning"
"$BIN" back >/dev/null
until_state "not s['overview'] and s['settled']" || fail "back did not close the overview"
echo '{"layout:default": "tiles", "animation:enabled": false}' > "$MIELWM_CONFIG_DIR/config.json"
floating=$(state "[x['number'] for x in s['windows'] if x.get('workspace') is None][0]")
"$AEROSPACE" focus --window-id "$floating" >/dev/null # a workspace switch focuses a window on that workspace
until_state "[x['number'] for x in s['windows'] if x['id'] == s['focused']] == [$floating]" || fail "focus did not land on the floating window"
"$BIN" layout floating >/dev/null
until_state "all(x.get('workspace') == $first_ws for x in s['windows'])" || fail "the window did not tile again"

step "tiles: rescan keeps every window where it is"
"$BIN" refresh >/dev/null
settled || fail "a rescan moved windows: $(state 's["windows"]')"
until_state "len(s['windows']) == 2" || fail "a rescan lost a window"

step "tiles: close the focused window, then minimize the last one"
"$AEROSPACE" focus --window-id "$(state "$(win "$other")['number']")" >/dev/null
until_state "s['focused'] == $(win "$other")['id']" || fail "focus did not land on $other"
"$BIN" close >/dev/null
until_state "len(s['windows']) == 1" || fail "close left $(state 'len(s["windows"])') windows"
until_windows "'$other' not in w" || fail "$other is still open"
"$AEROSPACE" focus --window-id "$(state "$(win "$first")['number']")" >/dev/null
until_state "s['focused'] == $(win "$first")['id']" || fail "focus did not land on $first"
"$BIN" minimize >/dev/null
until_state "$(win "$first")['minimized']" || fail "$first did not minimize"

step "tiles: quit: the test copy goes and leaves nothing behind"
quit_and_check

echo "PASS"
