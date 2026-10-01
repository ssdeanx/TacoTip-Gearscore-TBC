#!/usr/bin/env bash
# Run the whole offline verification matrix.
#
# Every harness is a plain-Lua script that loads the real addon files against a
# mocked client, so this needs no game and no WoWUnit. Run it from anywhere:
#
#   bash TacoTip_Forever/Tests/harness/run_all.sh
#
# Exits non-zero if any invocation fails.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON="$(cd "$HERE/../.." && pwd)"
LUA="${LUA:-lua5.1}"

cd "$ADDON" || exit 1

pass=0
fail=0
failed_invocations=()

run() {
    local label="$1"
    shift
    local out
    out="$("$LUA" "$@" 2>&1)"
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass=$((pass + 1))
        printf '  ok    %s\n' "$label"
    else
        fail=$((fail + 1))
        failed_invocations+=("$label")
        printf '  FAIL  %s\n' "$label"
        printf '%s\n' "$out" | sed 's/^/          /'
    fi
}

# The five supported clients: "<projectId> <iface> <family> <bracket> <label> [pipeline]"
# The first two fields are the positional args every per-client harness takes;
# the rest differ per harness.
CLIENTS_ERA="2 11509"
CLIENTS_TBC="5 20506"
CLIENTS_TITANFORGE="11 38002"
CLIENTS_FOREVER="1 16001"
CLIENTS_RETAIL="1 120100"

echo "== client detection =="
run "detect_test" Tests/harness/detect_test.lua
run "inspect_test" Tests/harness/inspect_test.lua

echo "== locale and fonts =="
run "locale_test" Tests/harness/locale_test.lua
run "font_test"   Tests/harness/font_test.lua

echo "== addon load, both GetBuildInfo slot layouts =="
for slot in slot4 slot7; do
    run "load_test CLASSIC_ERA   $slot"  Tests/harness/load_test.lua 2  11509 $slot classicEra 200  ERA
    run "load_test TBC_ANNIV    $slot"  Tests/harness/load_test.lua 5  20506 $slot tbc        400  TBC
    run "load_test TITANFORGE   $slot"  Tests/harness/load_test.lua 11 38002 $slot titanforge 1000 TITANFORGE
    run "load_test FOREVER      $slot"  Tests/harness/load_test.lua 1  16001 $slot forever     200  FOREVER   pipeline
    run "load_test RETAIL       $slot"  Tests/harness/load_test.lua 1  120100 $slot retail    1000 RETAIL    pipeline
done

echo "== options UI build =="
run "options_test CLASSIC_ERA"        Tests/harness/options_test.lua 2  11509 CLASSIC_ERA
run "options_test TBC_ANNIV"          Tests/harness/options_test.lua 5  20506 TBC_ANNIV
run "options_test TITANFORGE"         Tests/harness/options_test.lua 11 38002 TITANFORGE
run "options_test FOREVER"            Tests/harness/options_test.lua 1  16001 FOREVER   pipeline
run "options_test RETAIL"             Tests/harness/options_test.lua 1  120100 RETAIL    pipeline
run "options_test legacy path"        Tests/harness/options_test.lua 2  11509 CLASSIC_ERA legacy nosettings
run "options_test no colour picker"   Tests/harness/options_test.lua 11 38002 TITANFORGE legacy nocolor nosharedmedia

echo "== settings frame: reachability, binding, persistence, registration =="
# <projectId> <iface> <label> <pipeline|legacy> <settings|nosettings> <pawn|nopawn>
for spec in "2 11509 CLASSIC_ERA legacy" "5 20506 TBC_ANNIV legacy" \
            "11 38002 TITANFORGE legacy" "1 16001 FOREVER pipeline" "1 120100 RETAIL pipeline"; do
    set -- $spec
    pid="$1"; iface="$2"; label="$3"; mode="$4"
    for reg in settings nosettings; do
        for pawn in pawn nopawn; do
            run "settings_test $label $reg $pawn" \
                Tests/harness/settings_test.lua "$pid" "$iface" "$label" "$mode" "$reg" "$pawn"
        done
    done
done

echo "== file-scope robustness: a missing Blizzard global must not abort the load =="
# main.lua is the last file in the toc and every feature it defines after a throw
# is silently lost, so each of these proves a file-scope dependency is GUARDED
# rather than fatal. The mocked hooksecurefunc throws on an absent target, exactly
# like the real one, so an unguarded hook would fail the load here.
for spec in "2 11509 classicEra 200 ERA legacy" "1 120100 retail 1000 RETAIL pipeline"; do
    set -- $spec
    run "load_test $5 without GameTooltip_SetDefaultAnchor" \
        Tests/harness/load_test.lua "$1" "$2" slot4 "$3" "$4" "$5" "$6" GameTooltip_SetDefaultAnchor
done

echo "== tooltip pipeline =="
run "tooltip_test CLASSIC_ERA"  Tests/harness/tooltip_test.lua 2  11509 CLASSIC_ERA
run "tooltip_test TBC_ANNIV"    Tests/harness/tooltip_test.lua 5  20506 TBC_ANNIV
run "tooltip_test TITANFORGE"   Tests/harness/tooltip_test.lua 11 38002 TITANFORGE
run "tooltip_test FOREVER"      Tests/harness/tooltip_test.lua 1  16001 FOREVER   pipeline
run "tooltip_test RETAIL"       Tests/harness/tooltip_test.lua 1  120100 RETAIL    pipeline

echo "== static talent table =="
run "talent_check CLASSIC_ERA"  Tests/harness/talent_check.lua 2  11509 CLASSIC_ERA
run "talent_check TBC_ANNIV"    Tests/harness/talent_check.lua 5  20506 TBC_ANNIV
run "talent_check TITANFORGE"   Tests/harness/talent_check.lua 11 38002 TITANFORGE

echo
echo "-------------------------------------------------------------"
printf 'TOTAL %d invocations: %d passed, %d failed\n' "$((pass + fail))" "$pass" "$fail"
if [ "$fail" -ne 0 ]; then
    for f in "${failed_invocations[@]}"; do
        printf '  failed: %s\n' "$f"
    done
    exit 1
fi
echo "-------------------------------------------------------------"
exit 0
