#!/usr/bin/env bash
set -euo pipefail

# Focused S2 output contract and falsification controls.
#
# This script validates the S2 evidence contract: it checks cardinality, exact
# rows, and hashes, and it runs the three permanent falsification controls
# required by the S2 proof contract. It is deliberately NOT the semantic
# oracle: every semantic row is computed by the tracked Lean evidence module
# from the imported production programs. This script can only reject.
#
# Usage:
#   test-s2-contract.sh [evidence-runner] [artifact-dir] [lean-source]

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
runner="${1:-$script_dir/s2-evidence}"
artifacts="${2:-$script_dir/KeriBlaster/nix-generated}"
lean_source="${3:-$script_dir/KeriBlaster/S2Evidence.lean}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  printf 'test-s2-contract: %s\n' "$*" >&2
  exit 1
}

# The exact production titles. Each must have one literal import directive and
# one generated artifact. Declared once so no control can silently cover fewer.
titles=(
  'checkpoint.checkpoint.spend'
  'hash_proof.hash_proof.mint'
  'checkpoint_observer.observer_lifecycle.withdraw'
  'checkpoint_observer.observer_lifecycle.publish'
  'checkpoint_observer.observer_advance.withdraw'
  'checkpoint_observer.observer_advance.publish'
  'checkpoint_observer.observer_enforcement.withdraw'
  'checkpoint_observer.observer_enforcement.publish'
)

# The observer families whose withdraw/publish programs are byte-identical and
# whose purpose behaviour is therefore established by the applied context
# alone. One purpose-binding row is emitted per family; declaring the set here
# keeps a check from silently accepting fewer rows than were promised.
observers=(
  observer_lifecycle
  observer_advance
  observer_enforcement
)

# The permanent falsification controls. The count is asserted after execution
# so a dropped control fails the check instead of silently shrinking it.
controls=(
  removed-import
  substituted-artifact
  literalized-evidence
  duplicated-context
)

# Count emitted purpose-binding rows whose computed distinct-context count is
# strictly below the applied-context count. Both numbers are read out of the
# row rather than compared against a written-down expectation, so this stays
# correct if the fixture set grows.
count_dropped_binding_rows() {
  awk '
    /^S2\.purpose-binding / {
      applied = ""; distinct = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^applied_contexts=/)  { split($i, a, "="); applied  = a[2] }
        if ($i ~ /^distinct_contexts=/) { split($i, d, "="); distinct = d[2] }
      }
      if (applied != "" && distinct != "" && distinct + 0 < applied + 0) n++
    }
    END { print n + 0 }
  ' "$1"
}

count_binding_rows() {
  grep -cE '^S2\.purpose-binding ' "$1" || true
}

count_import_directives() {
  grep -cE '^#import_uplc [A-Za-z]+ PlutusV3 single_cbor_hex "nix-generated/' \
    "$1" || true
}

# --- Live harness controls -------------------------------------------------
# These run before any RED assertion so a broken harness cannot be mistaken
# for a contract verdict, and so absence is never inferred from a method that
# was never shown able to detect presence.

[[ $((20 + 22)) -eq 42 ]] || fail "bash arithmetic control failed"

captured_rc=0
( exit 3 ) || captured_rc=$?
[[ $captured_rc -eq 3 ]] || fail "failure-capture control did not observe exit 3"

[[ -f "$lean_source" ]] \
  || fail "tracked Lean evidence source absent: $lean_source"

# Positive control: the matcher finds exactly the eight literal directives in
# the tracked source.
present="$(count_import_directives "$lean_source")"
[[ "$present" -eq ${#titles[@]} ]] \
  || fail "expected ${#titles[@]} literal import directives, matched $present"

# Every declared title must have its own literal directive, so a duplicated
# import cannot stand in for a missing one.
for title in "${titles[@]}"; do
  grep -Fq "\"nix-generated/$title.hex\"" "$lean_source" \
    || fail "no literal import directive for production title: $title"
done

# Negative control for the removed-import matcher: with one directive deleted
# the same matcher must report a shortfall. This proves the removed-import
# control can fail before it is ever relied on.
perturbed="$work/removed-import.lean"
awk '!/^#import_uplc checkpointSpend /' "$lean_source" >"$perturbed"
perturbed_count="$(count_import_directives "$perturbed")"
[[ "$perturbed_count" -eq $(( ${#titles[@]} - 1 )) ]] \
  || fail "removed-import matcher did not detect a deleted directive"
if grep -Fq '"nix-generated/checkpoint.checkpoint.spend.hex"' "$perturbed"; then
  fail "removed-import perturbation did not remove the intended directive"
fi

# --- Missing implementation boundary ---------------------------------------
# The three permanent controls each require rebuilding and re-running the
# evidence path against a perturbed input. That path does not exist until the
# flake generates the exact artifacts and wires the evidence executable.

if [[ ! -x "$runner" ]]; then
  printf 'RED: S2 evidence runner absent after live harness controls: %s\n' \
    "$runner" >&2
  printf 'RED: the following permanent controls cannot execute: %s\n' \
    "${controls[*]}" >&2
  exit 68
fi

if [[ ! -d "$artifacts" ]]; then
  printf 'RED: generated artifact directory absent: %s\n' "$artifacts" >&2
  exit 68
fi

for title in "${titles[@]}"; do
  [[ -s "$artifacts/$title.hex" ]] \
    || fail "generated artifact absent or empty: $artifacts/$title.hex"
done

executed=()

# --- Control 1: removed import ---------------------------------------------
# Deleting one exact production import must make the evidence path fail. An
# import that can be removed without consequence is not load-bearing.

control_removed_import() {
  local rc=0
  S2_ARTIFACTS="$artifacts" S2_CONTROL=removed-import \
    S2_CONTROL_TITLE="${titles[0]}" \
    "$runner" >"$work/removed-import.out" 2>"$work/removed-import.err" || rc=$?
  [[ $rc -ne 0 ]] \
    || fail "removed-import control succeeded; the import is not load-bearing"
  grep -Fq "${titles[0]}" "$work/removed-import.err" \
    || fail "removed-import control lost its diagnostic for ${titles[0]}"
}

# --- Control 2: substituted artifact ---------------------------------------
# Replacing a generated artifact with a non-production program must fail on
# program identity, not merely on decoding.

control_substituted_artifact() {
  local rc=0
  S2_ARTIFACTS="$artifacts" S2_CONTROL=substituted-artifact \
    S2_CONTROL_TITLE="${titles[0]}" \
    "$runner" >"$work/substituted.out" 2>"$work/substituted.err" || rc=$?
  [[ $rc -ne 0 ]] \
    || fail "substituted-artifact control succeeded; identity is unchecked"
  grep -Fq "${titles[0]}" "$work/substituted.err" \
    || fail "substituted-artifact control lost its identity diagnostic"
}

# --- Control 3: literalized evidence ---------------------------------------
# Replacing a computed inventory or live row with a literal, while the
# controlled input is perturbed, must fail. This is what stops a fabricated
# row from passing as computed evidence.

control_literalized_evidence() {
  local rc=0
  S2_ARTIFACTS="$artifacts" S2_CONTROL=literalized-evidence \
    "$runner" >"$work/literalized.out" 2>"$work/literalized.err" || rc=$?
  [[ $rc -ne 0 ]] \
    || fail "literalized-evidence control succeeded; a literal row can pass"
  grep -Fq 'literalized' "$work/literalized.err" \
    || fail "literalized-evidence control lost its diagnostic"
}

# --- Control 4: duplicated context ------------------------------------------
# `distinct_contexts` is claimed to be derived from the contexts a purpose
# block actually applied. Until the applied set contains a duplicate, that
# derivation and the constant it replaced are indistinguishable.
#
# So the difference is caused, not awaited: an unperturbed baseline run must
# report every binding row with distinct == applied, and the perturbed run
# must report every binding row with distinct < applied. A literal, or a
# `distinct` that is secretly `applied`, fails one of the two halves. The
# evidence runner enforces the same relation itself and exits nonzero, so a
# broken derivation is caught twice, independently.

control_duplicated_context() {
  local rc=0
  S2_ARTIFACTS="$artifacts" \
    "$runner" >"$work/baseline.out" 2>"$work/baseline.err" || rc=$?
  [[ $rc -eq 0 ]] \
    || fail "unperturbed baseline run failed (rc=$rc); see $work/baseline.err"

  local baseline_rows baseline_dropped
  baseline_rows="$(count_binding_rows "$work/baseline.out")"
  [[ "$baseline_rows" -eq ${#observers[@]} ]] \
    || fail "baseline emitted $baseline_rows binding rows, expected ${#observers[@]}"
  baseline_dropped="$(count_dropped_binding_rows "$work/baseline.out")"
  [[ "$baseline_dropped" -eq 0 ]] \
    || fail "baseline already reports distinct<applied in $baseline_dropped rows; the duplicated-context control could not attribute a drop to its perturbation"

  rc=0
  S2_ARTIFACTS="$artifacts" S2_CONTROL=duplicated-context \
    "$runner" >"$work/duplicated.out" 2>"$work/duplicated.err" || rc=$?
  [[ $rc -eq 0 ]] \
    || fail "duplicated-context control did not complete (rc=$rc); see $work/duplicated.err"

  local dropped
  dropped="$(count_dropped_binding_rows "$work/duplicated.out")"
  [[ "$dropped" -eq ${#observers[@]} ]] \
    || fail "duplicated-context control: $dropped of ${#observers[@]} binding rows reported distinct<applied; the distinct count does not follow the applied contexts"

  # A pass that prints no quantity is indistinguishable from a pass that did
  # nothing. Both perturbed and unperturbed invocations run in a temporary
  # directory this script deletes on exit, so without this the numbers the
  # control turned on would never reach the durable gate log. Reporting only,
  # asserted above.
  printf 'S2.control-observed kind=duplicated-context observers=%s baseline_dropped=%s perturbed_dropped=%s\n' \
    "${#observers[@]}" "$baseline_dropped" "$dropped"
  grep -E '^S2\.purpose-binding ' "$work/baseline.out" \
    | sed 's/^/S2.control-observed baseline /'
  grep -E '^S2\.purpose-binding ' "$work/duplicated.out" \
    | sed 's/^/S2.control-observed perturbed /'
}

for control in "${controls[@]}"; do
  case "$control" in
    removed-import) control_removed_import ;;
    substituted-artifact) control_substituted_artifact ;;
    literalized-evidence) control_literalized_evidence ;;
    duplicated-context) control_duplicated_context ;;
    *) fail "unknown declared control: $control" ;;
  esac
  executed+=("$control")
done

[[ ${#executed[@]} -eq ${#controls[@]} ]] \
  || fail "executed ${#executed[@]} of ${#controls[@]} declared controls"

printf '%s\n' \
  "PASS: S2 contract validated ${#titles[@]} titles and executed controls: ${executed[*]}"
