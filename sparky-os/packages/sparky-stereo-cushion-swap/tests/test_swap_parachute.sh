#!/usr/bin/env bash
#
# test_swap_parachute.sh — synthetic-fixture unit test harness for
# cgm_swap_parachute.sh's guard logic.
#
# WHAT:
#   Drives cgm_swap_parachute.sh --dry-run --once against hand-built
#   /proc/meminfo + /proc/swaps fixtures (never the real ones) and asserts
#   on the printed decision arithmetic. Exercises: deploy hard-floor
#   trigger + its negative control, deploy rate-trigger + its negative
#   control, retract-guard margin pass/fail, retract-guard quiet-timer
#   pass/fail, the quiet-timer reset-on-danger behavior, idempotency
#   (deploy-when-on / retract-when-off are no-ops), and fail-safe
#   behavior on a malformed or missing /proc/meminfo.
#
# WHY:
#   Daniel's spec requires the guard logic be verified WITHOUT touching
#   live swap state. All scenarios below run with --dry-run and read
#   from throwaway fixture files under a private tmp dir, never from
#   /proc/meminfo or /proc/swaps. Every number here is SYNTHETIC — this
#   proves the arithmetic, not "contact with reality" (that's what the
#   separate real-/proc/meminfo dry-run demo is for; see README.md).
#
# WHO:
#   CGM Forge host-tooling verification, Daniel Campos Ramos, 2026-08-01.
#
# DEPS: bash, the daemon script itself (DAEMON path below), coreutils.
#
# USAGE: ./test_swap_parachute.sh   (exits 0 if all PASS, 1 if any FAIL)
#
# SPARKY STEREO OS (2026-10-10): run unchanged against the packaged daemon.
# Only these lines differ from Daniel's original: the daemon path, the
# scratch directory, and the area/settings the fixtures stand for.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON="${DAEMON:-${SCRIPT_DIR}/../sbin/cushion-swap}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/cushion-swap-test.XXXXXX")"
export CUSHION_SWAP_AREA=/fake/swapfile CUSHION_SWAP_CONFIG=/nonexistent FSTAB_PATH=/nonexistent
trap 'rm -rf "$WORKDIR"' EXIT

readonly KIB_PER_GIB=1048576
PASS_COUNT=0
FAIL_COUNT=0

# gib_to_kib N -> N GiB expressed in KiB (integer)
gib_to_kib() { echo $(( $1 * KIB_PER_GIB )); }

# write_meminfo path avail_kib swap_total_kib swap_free_kib
write_meminfo() {
    local path="$1" avail="$2" stotal="$3" sfree="$4"
    cat > "$path" <<EOF
MemTotal:       97957892 kB
MemFree:        63389304 kB
MemAvailable:   ${avail} kB
Buffers:          531424 kB
Cached:         11245620 kB
SwapCached:            0 kB
SwapTotal:      ${stotal} kB
SwapFree:       ${sfree} kB
EOF
}

# write_meminfo_broken path -- missing MemAvailable field entirely
write_meminfo_broken() {
    local path="$1"
    cat > "$path" <<EOF
MemTotal:       97957892 kB
MemFree:        63389304 kB
SwapTotal:             0 kB
SwapFree:              0 kB
EOF
}

# write_swaps path active(0|1)
write_swaps() {
    local path="$1" active="$2"
    if [[ "$active" == "1" ]]; then
        printf 'Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n/fake/swapfile                          file\t\t10485760\t2097152\t\t-1\n' > "$path"
    else
        printf 'Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n' > "$path"
    fi
}

# run_daemon test_name state_dir meminfo swaps now_epoch [extra env...]
# Captures combined stdout+stderr into $WORKDIR/<test_name>.out and
# returns the daemon's exit code via $?.
run_daemon() {
    local name="$1" state="$2" meminfo="$3" swaps="$4" now="$5"
    mkdir -p "$state"
    MEMINFO_PATH="$meminfo" SWAPS_PATH="$swaps" STATE_DIR="$state" NOW_EPOCH="$now" \
        "$DAEMON" --dry-run --once > "${WORKDIR}/${name}.out" 2>&1
    return $?
}

assert_contains() {
    local test_name="$1" needle="$2" file="$3"
    if grep -qF -- "$needle" "$file"; then
        echo "  PASS: ${test_name}: found '${needle}'"
        PASS_COUNT=$((PASS_COUNT+1))
    else
        echo "  FAIL: ${test_name}: expected to find '${needle}' -- actual output:"
        sed 's/^/       | /' "$file"
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
}

assert_not_contains() {
    local test_name="$1" needle="$2" file="$3"
    if grep -qF -- "$needle" "$file"; then
        echo "  FAIL: ${test_name}: did NOT expect to find '${needle}' -- actual output:"
        sed 's/^/       | /' "$file"
        FAIL_COUNT=$((FAIL_COUNT+1))
    else
        echo "  PASS: ${test_name}: correctly absent '${needle}'"
        PASS_COUNT=$((PASS_COUNT+1))
    fi
}

echo "=============================================================="
echo "TEST 1: deploy hard-floor trigger (MemAvailable < 6 GiB)"
echo "=============================================================="
T1_STATE="${WORKDIR}/t1_state"; T1_MEM="${WORKDIR}/t1_meminfo"; T1_SWP="${WORKDIR}/t1_swaps"
write_meminfo "$T1_MEM" "$(gib_to_kib 4)" 0 0
write_swaps "$T1_SWP" 0
run_daemon t1 "$T1_STATE" "$T1_MEM" "$T1_SWP" 100000
assert_contains "t1-hard-trigger-fires" "hard_trigger=1" "${WORKDIR}/t1.out"
assert_contains "t1-deploy-fires" "deploy_trigger=1" "${WORKDIR}/t1.out"
assert_contains "t1-would-deploy" "would run" "${WORKDIR}/t1.out"

echo
echo "=============================================================="
echo "TEST 2: deploy negative control (MemAvailable well above 6 GiB, no rate history)"
echo "=============================================================="
T2_STATE="${WORKDIR}/t2_state"; T2_MEM="${WORKDIR}/t2_meminfo"; T2_SWP="${WORKDIR}/t2_swaps"
write_meminfo "$T2_MEM" "$(gib_to_kib 40)" 0 0
write_swaps "$T2_SWP" 0
run_daemon t2 "$T2_STATE" "$T2_MEM" "$T2_SWP" 100000
assert_contains "t2-hard-trigger-absent" "hard_trigger=0" "${WORKDIR}/t2.out"
assert_contains "t2-deploy-absent" "deploy_trigger=0" "${WORKDIR}/t2.out"
assert_not_contains "t2-no-deploy-action" "would run" "${WORKDIR}/t2.out"

echo
echo "=============================================================="
echo "TEST 3: deploy rate-trigger (MemAvailable < 12GiB soft floor, falling"
echo "         3 GiB in 3s == 1 GiB/s >> 1 GiB/10s threshold)"
echo "=============================================================="
T3_STATE="${WORKDIR}/t3_state"; T3_SWP="${WORKDIR}/t3_swaps"
write_swaps "$T3_SWP" 0
T3_MEM_A="${WORKDIR}/t3_meminfo_a"; write_meminfo "$T3_MEM_A" "$(gib_to_kib 13)" 0 0
run_daemon t3a "$T3_STATE" "$T3_MEM_A" "$T3_SWP" 200000
assert_contains "t3a-first-sample-no-trigger" "deploy_trigger=0" "${WORKDIR}/t3a.out"
T3_MEM_B="${WORKDIR}/t3_meminfo_b"; write_meminfo "$T3_MEM_B" "$(gib_to_kib 10)" 0 0
run_daemon t3b "$T3_STATE" "$T3_MEM_B" "$T3_SWP" 200003
assert_contains "t3b-rate-trigger-fires" "rate_trigger=1" "${WORKDIR}/t3b.out"
assert_contains "t3b-deploy-fires" "deploy_trigger=1" "${WORKDIR}/t3b.out"
assert_contains "t3b-would-deploy" "would run" "${WORKDIR}/t3b.out"

echo
echo "=============================================================="
echo "TEST 4: rate-trigger negative control (below 12GiB soft floor but"
echo "         falling slowly: ~10MiB over 3s, well under 1GiB/10s)"
echo "=============================================================="
T4_STATE="${WORKDIR}/t4_state"; T4_SWP="${WORKDIR}/t4_swaps"
write_swaps "$T4_SWP" 0
T4_MEM_A="${WORKDIR}/t4_meminfo_a"; write_meminfo "$T4_MEM_A" "11534336" 0 0
run_daemon t4a "$T4_STATE" "$T4_MEM_A" "$T4_SWP" 300000
T4_MEM_B="${WORKDIR}/t4_meminfo_b"; write_meminfo "$T4_MEM_B" "11524336" 0 0
run_daemon t4b "$T4_STATE" "$T4_MEM_B" "$T4_SWP" 300003
assert_contains "t4b-rate-trigger-absent" "rate_trigger=0" "${WORKDIR}/t4b.out"
assert_contains "t4b-deploy-absent" "deploy_trigger=0" "${WORKDIR}/t4b.out"
assert_not_contains "t4b-no-deploy-action" "would run" "${WORKDIR}/t4b.out"

echo
echo "=============================================================="
echo "TEST 5: retract-guard PASS (swap_used=5GiB, avail=40GiB > 25GiB"
echo "         margin, quiet_elapsed=700s >= 600s required)"
echo "=============================================================="
T5_STATE="${WORKDIR}/t5_state"; mkdir -p "$T5_STATE"
printf '0 0 999300 0\n' > "${T5_STATE}/state"   # last_danger_epoch=999300, NOW will be 1000000 (700s quiet)
T5_MEM="${WORKDIR}/t5_meminfo"; T5_SWP="${WORKDIR}/t5_swaps"
write_meminfo "$T5_MEM" "$(gib_to_kib 40)" "$(gib_to_kib 6)" "$(gib_to_kib 1)"  # swap_total=6G swap_free=1G -> used=5G
write_swaps "$T5_SWP" 1
run_daemon t5 "$T5_STATE" "$T5_MEM" "$T5_SWP" 1000000
assert_contains "t5-margin-pass" "margin_pass=yes" "${WORKDIR}/t5.out"
assert_contains "t5-quiet-pass" "quiet_pass=yes" "${WORKDIR}/t5.out"
assert_contains "t5-retract-ok" "retract_ok=1" "${WORKDIR}/t5.out"
assert_contains "t5-would-retract" "would run" "${WORKDIR}/t5.out"

echo
echo "=============================================================="
echo "TEST 6: retract-guard FAIL on arithmetic margin -- the illustrative"
echo "         '~12GiB used post-rescue' scenario: swap_used=12GiB,"
echo "         avail=25GiB, needs > 32GiB. Quiet timer already satisfied"
echo "         so ONLY the margin fails (isolated variable)."
echo "=============================================================="
T6_STATE="${WORKDIR}/t6_state"; mkdir -p "$T6_STATE"
printf '0 0 999300 0\n' > "${T6_STATE}/state"
T6_MEM="${WORKDIR}/t6_meminfo"; T6_SWP="${WORKDIR}/t6_swaps"
write_meminfo "$T6_MEM" "$(gib_to_kib 25)" "$(gib_to_kib 13)" "$(gib_to_kib 1)"  # swap_total=13G swap_free=1G -> used=12G
write_swaps "$T6_SWP" 1
run_daemon t6 "$T6_STATE" "$T6_MEM" "$T6_SWP" 1000000
assert_contains "t6-swap-used-12gib" "SwapUsed=12.00GiB" "${WORKDIR}/t6.out"
assert_contains "t6-required-32gib" "required_avail(>swap_used+20GiB)=32.00GiB" "${WORKDIR}/t6.out"
assert_contains "t6-margin-fail" "margin_pass=no" "${WORKDIR}/t6.out"
assert_contains "t6-quiet-pass-isolated" "quiet_pass=yes" "${WORKDIR}/t6.out"
assert_contains "t6-retract-blocked" "retract_ok=0" "${WORKDIR}/t6.out"
assert_not_contains "t6-no-retract-action" "would run" "${WORKDIR}/t6.out"

echo
echo "=============================================================="
echo "TEST 7: retract-guard FAIL on quiet-timer (margin passes fine,"
echo "         but a deploy-trigger fired only 30s ago -- must wait"
echo "         for the full 600s quiet window)"
echo "=============================================================="
T7_STATE="${WORKDIR}/t7_state"; mkdir -p "$T7_STATE"
printf '0 0 999970 0\n' > "${T7_STATE}/state"  # last_danger 30s before NOW=1000000
T7_MEM="${WORKDIR}/t7_meminfo"; T7_SWP="${WORKDIR}/t7_swaps"
write_meminfo "$T7_MEM" "$(gib_to_kib 40)" "$(gib_to_kib 3)" "$(gib_to_kib 1)"  # used=2G, margin needs >22G, avail=40G passes
write_swaps "$T7_SWP" 1
run_daemon t7 "$T7_STATE" "$T7_MEM" "$T7_SWP" 1000000
assert_contains "t7-margin-pass" "margin_pass=yes" "${WORKDIR}/t7.out"
assert_contains "t7-quiet-fail" "quiet_pass=no" "${WORKDIR}/t7.out"
assert_contains "t7-quiet-elapsed-30s" "quiet_elapsed=30s" "${WORKDIR}/t7.out"
assert_contains "t7-retract-blocked" "retract_ok=0" "${WORKDIR}/t7.out"
assert_not_contains "t7-no-retract-action" "would run" "${WORKDIR}/t7.out"

echo
echo "=============================================================="
echo "TEST 8: quiet-timer RESET -- a deploy-trigger firing resets"
echo "         last_danger_epoch to 'now', observed via a second"
echo "         immediate cycle showing quiet_elapsed back near 0"
echo "=============================================================="
T8_STATE="${WORKDIR}/t8_state"; mkdir -p "$T8_STATE"
printf '0 0 999300 0\n' > "${T8_STATE}/state"  # was quiet for 700s as of NOW=1000000
T8_SWP="${WORKDIR}/t8_swaps"; write_swaps "$T8_SWP" 0
T8_MEM_DANGER="${WORKDIR}/t8_meminfo_danger"; write_meminfo "$T8_MEM_DANGER" "$(gib_to_kib 4)" 0 0  # hard trigger
run_daemon t8a "$T8_STATE" "$T8_MEM_DANGER" "$T8_SWP" 1000000
assert_contains "t8a-danger-fires" "deploy_trigger=1" "${WORKDIR}/t8a.out"
# Immediately re-evaluate at the SAME epoch: quiet_elapsed must now read 0,
# proving last_danger_epoch was reset from 999300 to 1000000 by the prior cycle.
run_daemon t8b "$T8_STATE" "$T8_MEM_DANGER" "$T8_SWP" 1000000
assert_contains "t8b-quiet-reset-to-zero" "quiet_elapsed=0s" "${WORKDIR}/t8b.out"

echo
echo "=============================================================="
echo "TEST 9: idempotent DEPLOY -- deploy_trigger=1 but swap already"
echo "         active => no action attempted (no 'would run' logged)"
echo "=============================================================="
T9_STATE="${WORKDIR}/t9_state"; T9_MEM="${WORKDIR}/t9_meminfo"; T9_SWP="${WORKDIR}/t9_swaps"
write_meminfo "$T9_MEM" "$(gib_to_kib 4)" "$(gib_to_kib 2)" "$(gib_to_kib 1)"
write_swaps "$T9_SWP" 1
run_daemon t9 "$T9_STATE" "$T9_MEM" "$T9_SWP" 100000
assert_contains "t9-trigger-still-fires" "deploy_trigger=1" "${WORKDIR}/t9.out"
assert_not_contains "t9-no-op-already-on" "would run" "${WORKDIR}/t9.out"

echo
echo "=============================================================="
echo "TEST 10: idempotent RETRACT -- retract conditions hold but swap"
echo "         already inactive => no action attempted"
echo "=============================================================="
T10_STATE="${WORKDIR}/t10_state"; mkdir -p "$T10_STATE"
printf '0 0 999300 0\n' > "${T10_STATE}/state"
T10_MEM="${WORKDIR}/t10_meminfo"; T10_SWP="${WORKDIR}/t10_swaps"
write_meminfo "$T10_MEM" "$(gib_to_kib 40)" "$(gib_to_kib 3)" "$(gib_to_kib 1)"
write_swaps "$T10_SWP" 0   # swap already OFF
run_daemon t10 "$T10_STATE" "$T10_MEM" "$T10_SWP" 1000000
assert_contains "t10-retract-conditions-hold-but-inactive" "retract_ok=1" "${WORKDIR}/t10.out"
assert_not_contains "t10-no-op-already-off" "would run" "${WORKDIR}/t10.out"

echo
echo "=============================================================="
echo "TEST 11: fail-safe on malformed /proc/meminfo (missing field)"
echo "         -- must log an error and do nothing, never crash"
echo "=============================================================="
T11_STATE="${WORKDIR}/t11_state"; T11_MEM="${WORKDIR}/t11_meminfo"; T11_SWP="${WORKDIR}/t11_swaps"
write_meminfo_broken "$T11_MEM"
write_swaps "$T11_SWP" 0
run_daemon t11 "$T11_STATE" "$T11_MEM" "$T11_SWP" 100000
T11_RC=$?
if [[ $T11_RC -eq 0 ]]; then
    echo "  PASS: t11-exit-code-clean: daemon exited 0 despite malformed meminfo"
    PASS_COUNT=$((PASS_COUNT+1))
else
    echo "  FAIL: t11-exit-code-clean: daemon exited ${T11_RC}"
    FAIL_COUNT=$((FAIL_COUNT+1))
fi
assert_contains "t11-error-logged" "ERROR" "${WORKDIR}/t11.out"
assert_not_contains "t11-no-action-attempted" "would run" "${WORKDIR}/t11.out"

echo
echo "=============================================================="
echo "TEST 12: fail-safe on missing /proc/meminfo file entirely"
echo "=============================================================="
T12_STATE="${WORKDIR}/t12_state"; T12_SWP="${WORKDIR}/t12_swaps"
write_swaps "$T12_SWP" 0
run_daemon t12 "$T12_STATE" "${WORKDIR}/does_not_exist_meminfo" "$T12_SWP" 100000
T12_RC=$?
if [[ $T12_RC -eq 0 ]]; then
    echo "  PASS: t12-exit-code-clean: daemon exited 0 despite missing meminfo file"
    PASS_COUNT=$((PASS_COUNT+1))
else
    echo "  FAIL: t12-exit-code-clean: daemon exited ${T12_RC}"
    FAIL_COUNT=$((FAIL_COUNT+1))
fi
assert_contains "t12-error-logged" "ERROR" "${WORKDIR}/t12.out"

echo
echo "=============================================================="
echo "SUMMARY: ${PASS_COUNT} passed, ${FAIL_COUNT} failed (out of $((PASS_COUNT+FAIL_COUNT)))"
echo "=============================================================="
if [[ "$FAIL_COUNT" -eq 0 ]]; then
    echo "ALL GREEN"
    exit 0
else
    echo "FAILURES PRESENT"
    exit 1
fi
