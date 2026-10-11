#!/usr/bin/env bash
# Run the TacoTip_Extras offline verification harness.
#
# Plain-Lua, no game and no WoWUnit: it loads the real add-on files from the real
# TOC against a mocked client, once per supported client. Run it from anywhere:
#
#   bash TacoTip_Extras/Tests/harness/run_all.sh
#
# EVERY interpreter in this list must pass. An interpreter counts as covered
# only once measured, so a script that tries one and reports "green" has not
# verified anything about the other two:
#
#   for i in lua5.1 lua5.4 luajit; do ... done
#
# Set LUA=<interp> to run exactly one.
#
# Exits non-zero if any invocation fails, and names the failing invocation.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON="$(cd "$HERE/../.." && pwd)"

cd "$ADDON" || exit 1

TEST="Tests/harness/load_test.lua"

pass=0
fail=0
failed_invocations=()

run() {
    local label="$1"
    shift
    local out
    out="$("$@" 2>&1)"
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

if [ -n "${LUA:-}" ]; then
    INTERPRETERS="$LUA"
else
    INTERPRETERS="lua5.1 lua5.4 luajit"
fi

# The matrix, as "<client> <variant> <label>".
#
# These are not ten copies of the same test. The harness ASSERTS the adapter's
# verdict, the raise set, the scoring contract and WHICH DRIVER BRANCH each
# client takes against the environment it was handed, so each entry pins a
# different branch of the code:
#
#   classic_era / tbc / titanforge   GameTooltip DOES declare OnTooltipSetUnit
#                                    and OnTooltipSetItem (Classic family XML),
#                                    so the driver must be "unit-hook" and the
#                                    OnUpdate poll must never be hooked at all.
#   forever / retail                 GameTooltip declares NEITHER (the only
#                                    occurrence of either name on origin/live
#                                    and origin/forever is an XML SCHEMA in
#                                    Blizzard_SharedXML/UI.xsd), so the hooks
#                                    must be skipped and a portable OnUpdate
#                                    driver used instead. These two are the runs
#                                    that crashed before.
#
#   devname   TacoTip's private table is published as "TacoTip_Forever" and
#             _G.TacoTip is nil, so the resolver must find it by scanning
#             loaded add-ons rather than by hardcoding the packaged name.
#   older     TacoTip 0.7.0 -- below the 0.8.0 minimum, so the capability gate
#             must still refuse it.
#   nocaps    The inspector is missing GetInventoryItemMixin and STILL has no
#             Version() method, so the gate must name the missing function
#             rather than report a version mismatch.
#   nostats   GetItemStats removed, so the gem/socket path must degrade: gems
#             still scored from the item link, empty sockets omitted.
#   nosettings  Settings removed, so Options must fall back to
#             InterfaceOptions_AddCategory with the childFrame.parent wiring and
#             still produce a usable panel.
SCENARIOS=(
    "classic_era ok       Classic Era, unit-hook driver"
    "tbc        ok        TBC Anniversary, unit-hook driver"
    "titanforge ok        Titanforge, unit-hook driver (regression guard)"
    "forever    ok        WoW Forever, poll driver + GetItemStats"
    "retail     ok        Retail, poll driver + GetItemStats"
    "classic_era devname  TacoTip private table under its dev-folder name"
    "classic_era older    TacoTip 0.7.0 below the enforced minimum"
    "classic_era nocaps   inspector missing GetInventoryItemMixin, no Version()"
    "classic_era nostats  Classic Era naturally has no GetItemStats"
    "forever    nostats  GetItemStats forced absent on a client that has it"
    "retail     nostats  GetItemStats forced absent on Retail too"
    "classic_era nosettings  legacy InterfaceOptions_AddCategory registration"
)

for interp in $INTERPRETERS; do
    if ! command -v "$interp" >/dev/null 2>&1; then
        fail=$((fail + 1))
        failed_invocations+=("$interp (interpreter not found)")
        printf '== %s ==\n  FAIL  interpreter not found\n' "$interp"
        continue
    fi

    printf '== %s (%s) ==\n' "$interp" "$("$interp" -v 2>&1 | head -1)"

    for spec in "${SCENARIOS[@]}"; do
        set -- $spec
        run "$1 $2" "$interp" "$TEST" "$1" "$2"
    done

    echo
done

echo "-------------------------------------------------------------"
printf 'TOTAL %d invocations: %d passed, %d failed\n' "$((pass + fail))" "$pass" "$fail"

# Optional lint pass, off by default so the load matrix above is the one thing
# this script guarantees. LINT=1 adds luacheck, which needs the add-on's own
# self-contained config and is REPORTED rather than asserted, because luacheck
# is not installed everywhere.
if [ "${LINT:-0}" = "1" ]; then
    echo
    if command -v luacheck >/dev/null 2>&1; then
        echo "== luacheck =="
        ( cd "$ADDON" && luacheck . --no-color )
        printf '  luacheck exit=%d\n' "$?"
    else
        echo "== luacheck == (not installed, skipped)"
    fi
    echo
fi

if [ "$fail" -ne 0 ]; then
    for f in "${failed_invocations[@]}"; do
        printf '  failed: %s\n' "$f"
    done
    echo "-------------------------------------------------------------"
    exit 1
fi
echo "-------------------------------------------------------------"
exit 0