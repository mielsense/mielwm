#!/bin/bash
# Measures mielwm against throwaway windows only: a separate test instance
# (--manage-only, its own socket and settings) manages 8 test windows and
# draws the overlay; your own windows and your running mielwm are left alone.
#
#   scripts/benchmark.sh [<bin dir>]     default: a fresh release build
#
# Prints a table (also saved to build/benchmark.txt): launch time, idle CPU
# and wakeups, a workspace switch, the overview held open, memory after it
# closes. Point <bin dir> at an older build to compare. The overlay shows on
# screen for about 15 s while it runs.
set -euo pipefail
cd "$(dirname "$0")/.."

# The test windows always come from this checkout, so two builds see the same windows.
swift build -c release --product mielwm-testwindows >/dev/null 2>&1
HELPER=$(swift build -c release --show-bin-path)/mielwm-testwindows
if [ $# -ge 1 ]; then BINDIR=$1; else
    swift build -c release --product mielwm >/dev/null 2>&1
    BINDIR=$(swift build -c release --show-bin-path)
fi
NAME=mielwm ENV=MIELWM
BIN=$BINDIR/$NAME
work=$(mktemp -d)
export "${ENV}_SOCKET=$work/s.sock" "${ENV}_CONFIG_DIR=$work/config"
mkdir -p "$work/config"

# CPU time, idle wakeups and memory footprint of one process, from the kernel.
cat > "$work/pstat.c" <<'C'
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <mach/mach_time.h>
int main(int argc, char **argv) {
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    struct rusage_info_v4 ri;
    if (argc < 2 || proc_pid_rusage(atoi(argv[1]), RUSAGE_INFO_V4, (rusage_info_t *)&ri) != 0) return 1;
    printf("%llu %llu %llu\n", (ri.ri_user_time + ri.ri_system_time) * tb.numer / tb.denom,
           ri.ri_pkg_idle_wkups, ri.ri_phys_footprint);
}
C
cc -O2 -o "$work/pstat" "$work/pstat.c"

helper="" app=""
cleanup() {
    [ -n "$app" ] && { "$BIN" quit >/dev/null 2>&1 || true; sleep 1; kill "$app" 2>/dev/null || true; }
    [ -n "$helper" ] && kill "$helper" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT
OUT=build/benchmark.txt; mkdir -p build; : > "$OUT"
say() { echo "$*" | tee -a "$OUT"; }
snap() { "$work/pstat" "$app"; }
now() { python3 -I -c 'import time; print(time.time())'; }
# row <label> <before> <after> <seconds>
row() {
    read -r c0 w0 _ <<< "$2"; read -r c1 w1 f1 <<< "$3"
    say "$(printf '| %-34s | %7.2f%% | %10.1f | %8.1f MB |' "$1" \
        "$(echo "($c1-$c0)/($4*10000000)" | bc -l)" "$(echo "($w1-$w0)/$4" | bc -l)" "$(echo "$f1/1048576" | bc -l)")"
}
managed() { "$BIN" state 2>/dev/null | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)["windows"]))' 2>/dev/null || echo 0; }

frames=""; for i in 0 1 2 3 4 5 6 7; do frames+="$((20 + 30 * i)),$((60 + 12 * i)),1200,800;"; done
# run <helper flags>: one instance against 8 fresh test windows; sets helper and app
run() {
    exec 3< <(exec "$HELPER" --frames "$frames" "$@" 2>/dev/null); read -r helper <&3
    sleep 1
    t0=$(now)
    env "${ENV}_TEST_OVERLAY=1" "$BIN" --manage-only "$helper" 2>/dev/null & app=$!
    for _ in $(seq 200); do [ "$(managed)" = 8 ] && break; sleep 0.05; done
    t1=$(now)
}
stop() { "$BIN" quit >/dev/null 2>&1 || true; sleep 1; kill "$app" "$helper" 2>/dev/null || true; app="" helper=""; sleep 1; }

run
say "$NAME, macOS $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string), 8 test windows of 1200x800"
say ""
say "Launch to 8 windows managed: $(printf '%.0f' "$(echo "($t1-$t0)*1000" | bc -l)") ms"
say ""
say "| Scenario                           |     CPU | Wakeups/s  | Memory      |"
say "|------------------------------------|---------|------------|-------------|"
sleep 3
s0=$(snap); sleep 30; s1=$(snap); row "Idle, 30 s" "$s0" "$s1" 30
s0=$(snap); "$BIN" workspace 2 >/dev/null; sleep 1; "$BIN" workspace 1 >/dev/null; sleep 1; s1=$(snap)
row "Two workspace switches, 2 s" "$s0" "$s1" 2
sleep 2
s0=$(snap); "$BIN" overview >/dev/null; sleep 10; s1=$(snap); row "Overview open, windows playing, 10 s" "$s0" "$s1" 10
s0=$(snap); "$BIN" overview >/dev/null; sleep 5; s1=$(snap); row "Closing, then 5 s" "$s0" "$s1" 5
s0=$(snap); sleep 40; s1=$(snap); row "45 s after closing (idle, 40 s)" "$s0" "$s1" 40
stop
run --still
sleep 3
"$BIN" overview >/dev/null; sleep 3 # past the opening flight
s0=$(snap); sleep 10; s1=$(snap); row "Overview open, windows still, 10 s" "$s0" "$s1" 10
say ""
say "CPU: share of one core. Wakeups: package idle wakeups per second. Memory: physical footprint."
