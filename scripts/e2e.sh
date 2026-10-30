#!/bin/bash
# Every end-to-end test, one after another: the on-screen system tests
# (Tests/MielSystemTests/WindowTests.swift), scripts/system-test.sh and
# scripts/barik-test.sh. Each puts throwaway windows on screen, so each waits
# until nobody has touched the keyboard or the mouse for 30 seconds. Exits
# non-zero if any part fails, after running the rest.
set -uo pipefail

cd "$(dirname "$0")/.."
swift build --build-tests >/dev/null 2>&1 || { swift build --build-tests; exit 1; }

# Seconds since the last key press, click or pointer move.
idle() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'; }
wait_for_idle() {
    local shown=""
    until [ "$(idle)" -ge 30 ]; do
        [ -z "$shown" ] && echo "   waiting until the Mac has been idle for 30 seconds" && shown=1
        sleep 5
    done
}

failed=()
run() {
    local name=$1
    shift
    echo "== $name"
    wait_for_idle
    if "$@"; then echo "   $name passed"; else echo "   $name FAILED"; failed+=("$name"); fi
}

run "on-screen system tests" env MIELWM_SYSTEM_TESTS=1 swift test --skip-build --filter WindowTests
run "system-test.sh" scripts/system-test.sh
run "barik-test.sh" scripts/barik-test.sh

if [ ${#failed[@]} -gt 0 ]; then
    echo "FAILED: ${failed[*]}"
    exit 1
fi
echo "PASS: every end-to-end test"
