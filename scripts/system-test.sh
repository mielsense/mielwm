#!/bin/bash
# End-to-end check on real macOS with throwaway windows only: opens two
# mielwm-testwindows windows, runs `mielwm --manage-only <their pid>`
# (no shortcuts, no overlay, never takes focus) and drives it over its socket:
#   pan away so the windows park, pan back so they return, let the app move
#   a window and check the canvas adopted it, park again, quit, and check
#   every window is back on screen.
# Exits non-zero on the first failed check. Never touches other windows.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build >/dev/null 2>&1 || { swift build; exit 1; }
BIN=.build/debug/mielwm
HELPER=.build/debug/mielwm-testwindows
export MIELWM_SOCKET="${TMPDIR:-/tmp}/mielwm-test-$$.sock"
# Its own settings, never yours: floating windows, so panning parks and brings them back.
export MIELWM_CONFIG_DIR="${TMPDIR:-/tmp}/mielwm-test-config-$$"
mkdir -p "$MIELWM_CONFIG_DIR"
echo '{"layout:default": "floating"}' > "$MIELWM_CONFIG_DIR/config.json"

helper_pid="" app_pid=""
cleanup() {
    [ -n "$app_pid" ] && kill "$app_pid" 2>/dev/null || true
    [ -n "$helper_pid" ] && kill "$helper_pid" 2>/dev/null || true
    rm -f "$MIELWM_SOCKET"
    rm -rf "$MIELWM_CONFIG_DIR"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
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
pan() { for _ in 1 2 3 4 5; do "$BIN" pan "$1" >/dev/null; sleep 0.3; done; sleep 1.5; }

step "open two test windows"
exec 3< <(exec "$HELPER" --frames "200,200,480,320;760,260,480,320" 2>/dev/null)
read -r helper_pid <&3
sleep 1

step "mielwm --manage-only $helper_pid"
"$BIN" --manage-only "$helper_pid" 2>/dev/null &
app_pid=$!
for _ in $(seq 50); do
    [ "$(state 'len(s["windows"])' 2>/dev/null || echo 0)" = 2 ] && break
    sleep 0.2
done
[ "$(state 'len(s["windows"])')" = 2 ] || fail "the canvas did not pick up both test windows"
start=$(windows 'w["PT-1"]["frame"]')

step "pan right until the windows leave the screen: they park"
pan right
[ "$(state 'all(x["parked"] for x in s["windows"])')" = True ] || fail "not parked: $(state 's["windows"]')"
[ "$(windows 'any(x["visible"] for x in w.values())')" = False ] || fail "a parked window is still on screen"

step "pan back: they return where they were"
pan left
[ "$(state 'any(x["parked"] for x in s["windows"])')" = False ] || fail "still parked after panning back"
[ "$(windows 'w["PT-1"]["frame"]')" = "$start" ] || fail "PT-1 came back at $(windows 'w["PT-1"]["frame"]'), not $start"

step "the app moves PT-1 by itself: the canvas adopts the move"
before=$(state '[x["frame"] for x in s["windows"] if x["title"]=="PT-1"][0]')
kill -USR1 "$helper_pid"
sleep 1.5
moved=$(python3 -I -c "b=$before; print([b[0]+100, b[1]+60, b[2], b[3]])")
[ "$(state '[x["frame"] for x in s["windows"] if x["title"]=="PT-1"][0]')" = "$moved" ] \
    || fail "canvas frame $(state '[x["frame"] for x in s["windows"] if x["title"]=="PT-1"][0]'), expected $moved"

step "park again, then quit: every window back on screen"
pan right
[ "$(state 'all(x["parked"] for x in s["windows"])')" = True ] || fail "not parked before quit"
"$BIN" quit >/dev/null
for _ in $(seq 50); do kill -0 "$app_pid" 2>/dev/null || break; sleep 0.1; done
kill -0 "$app_pid" 2>/dev/null && fail "the app did not quit"
app_pid=""
sleep 0.5
[ "$(windows 'all(x["visible"] for x in w.values()) and len(w)==2')" = True ] || fail "after quit: $(windows 'w')"

echo "PASS"
