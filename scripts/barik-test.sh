#!/bin/bash
# Barik end to end, without Barik's Xcode build: Barik's own AeroSpace
# detection and provider (scripts/barik, MIT) run through mielwm's `aerospace`
# command against `mielwm --manage-only` with two throwaway windows, its own
# socket and settings, and the hidden AeroSpace helper. Checks that Barik
# detects the helper by name, that every command Barik runs decodes into its
# models, that clicks reach the canvas, and that the helper quits with mielwm.
# Never touches other windows, Barik's config or a running Barik.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build >/dev/null 2>&1 || { swift build; exit 1; }
BIN=.build/debug/mielwm
WINDOWS=.build/debug/mielwm-testwindows
SHIM=.build/debug/mielwm-aerospace
work=$(mktemp -d)
export MIELWM_SOCKET="$work/s.sock" MIELWM_CONFIG_DIR="$work/config"
mkdir -p "$MIELWM_CONFIG_DIR"
echo '{"layout:default": "tiles"}' > "$MIELWM_CONFIG_DIR/config.json"

windows_pid="" app_pid="" helper_pid=""
cleanup() {
    [ -n "$app_pid" ] && kill "$app_pid" 2>/dev/null || true
    [ -n "$windows_pid" ] && kill "$windows_pid" 2>/dev/null || true
    [ -n "$helper_pid" ] && kill "$helper_pid" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo "== $*"; }
# A Python expression over `mielwm state` (as `s`), or over Barik's view (as `b`).
state() { "$BIN" state | python3 -I -c "import json,sys; s=json.load(sys.stdin); print($1)"; }
barik() { "$work/barik-check" "$SHIM" | python3 -I -c "import json,sys; b=json.load(sys.stdin); print($1)"; }

step "build Barik's AeroSpace code and the helper app"
swiftc -O scripts/barik/*.swift -o "$work/barik-check" 2>/dev/null || swiftc -O scripts/barik/*.swift -o "$work/barik-check"
HELPER="$work/AeroSpace.app"
mkdir -p "$HELPER/Contents/MacOS"
cp "$SHIM" "$HELPER/Contents/MacOS/AeroSpace"
cat > "$HELPER/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>my.miel.mielwm.aerospace-helper.test</string>
    <key>CFBundleName</key><string>AeroSpace</string>
    <key>CFBundleExecutable</key><string>AeroSpace</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force -s - "$HELPER" 2>/dev/null

step "open two test windows and mielwm --manage-only"
exec 3< <(exec "$WINDOWS" --frames "200,200,480,320;760,260,480,320" 2>/dev/null)
read -r windows_pid <&3
sleep 1
"$BIN" --manage-only "$windows_pid" 2>/dev/null &
app_pid=$!
for _ in $(seq 50); do
    [ "$(state 'len(s["windows"])' 2>/dev/null || echo 0)" = 2 ] && break
    sleep 0.2
done
[ "$(state 'len(s["windows"])')" = 2 ] || fail "the canvas did not pick up both test windows"

step "start the helper: Barik detects AeroSpace by name, mielwm's AeroSpace check (bobko.aerospace) does not"
open -g -n "$HELPER" --args --mielwm-pid "$app_pid"
for _ in $(seq 25); do helper_pid=$(pgrep -f "$HELPER/Contents/MacOS/AeroSpace" || true); [ -n "$helper_pid" ] && break; sleep 0.2; done
[ -n "$helper_pid" ] || fail "the helper did not start"
sleep 0.5
[ "$(barik 'b["detected"]')" = True ] || fail "Barik does not see a running AeroSpace"
[ "$(barik '"bobko.aerospace" in b["bundleIDs"]')" = False ] || fail "a real AeroSpace is running; quit it first"

step "Barik's provider reads every workspace and window"
view=$("$work/barik-check" "$SHIM")
python3 -I -c "import json,sys; json.loads(sys.argv[1])" "$view" || fail "Barik could not decode an answer: $view"
ids=$(state 'sorted(int(w["id"].split(":")[1]) for w in s["windows"])')
[ "$(barik 'sorted(w["id"] for x in b["spaces"] for w in x["windows"])')" = "$ids" ] || fail "Barik shows $view, the canvas has $ids"
[ "$(barik 'sorted({w["title"] for x in b["spaces"] for w in x["windows"]})')" = "['PT-1', 'PT-2']" ] || fail "titles: $view"
[ "$(barik 'sum(x["focused"] for x in b["spaces"])')" = 1 ] || fail "not one focused workspace: $view"

step "a click on a window focuses it"
for id in $(barik '" ".join(str(w["id"]) for x in b["spaces"] for w in x["windows"])'); do
    "$work/barik-check" "$SHIM" focus-window "$id"
    sleep 0.3
    [ "$(state 's["focused"].split(":")[1]')" = "$id" ] || fail "focus --window-id $id left focus on $(state 's["focused"]')"
done

step "a click on a workspace goes there"
for ws in $(barik '" ".join(x["id"] for x in b["spaces"])'); do
    "$work/barik-check" "$SHIM" focus-space "$ws"
    sleep 0.3
    [ "$("$SHIM" list-workspaces --focused --json)" = "[{\"workspace\":\"$ws\"}]" ] || fail "workspace $ws did not become current"
done

step "other commands print nothing and succeed"
[ -z "$("$SHIM" list-monitors --json)" ] || fail "an unknown command printed something"

step "quit mielwm: the helper quits too, and Barik gets empty lists"
"$BIN" quit >/dev/null
for _ in $(seq 50); do kill -0 "$app_pid" 2>/dev/null || break; sleep 0.2; done
app_pid=""
for _ in $(seq 25); do kill -0 "$helper_pid" 2>/dev/null || break; sleep 0.2; done
kill -0 "$helper_pid" 2>/dev/null && fail "the helper outlived mielwm"
helper_pid=""
[ "$("$SHIM" list-windows --all --json)" = "[]" ] || fail "without mielwm the command must print []"
[ -z "$("$SHIM" workspace 1)" ] || fail "without mielwm an action must print nothing"

echo "PASS"
