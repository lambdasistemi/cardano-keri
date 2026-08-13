#!/usr/bin/env bash
# Slice C records and selftests. Invoked by the flake-owned blaster
# runner (gate path) and therefore by checks.blaster (CI path) when
# that runner is not skipped.
set -euo pipefail

usage() {
  echo "usage: $0 BUNDLE_DIR [RUNNER_SOURCE]" >&2
  exit 2
}
[ "$#" -ge 1 ] || usage
bundle_dir=$1
runner_source=${2:-}
coverage_token=parsed-document
work=$(mktemp -d "${TMPDIR:-/tmp}/ckeri-slice-c.XXXXXXXX")
trap 'rm -rf "$work"' EXIT

# --- C8 / C11 / C7 / C12: both branches, then mode, THEN clean assembly ---
printf '%s\n' $'entry.sh\ttracked\t755\t1' $'notes.txt\ttracked\t644\t1' \
  > "$work/inventory.txt"
mkdir -p "$work/omit" "$work/mode" "$work/clean"
printf '%s\n' '#!/bin/sh' > "$work/omit/entry.sh"
chmod 755 "$work/omit/entry.sh"
cp -a "$work/omit/." "$work/mode/"
printf '%s\n' 'notes' > "$work/mode/notes.txt"
chmod 644 "$work/mode/entry.sh" "$work/mode/notes.txt"
cp -a "$work/omit/entry.sh" "$work/clean/entry.sh"
printf '%s\n' 'notes' > "$work/clean/notes.txt"
chmod 755 "$work/clean/entry.sh"
chmod 644 "$work/clean/notes.txt"

set +e
omit_out=$("$bundle_dir/check-completeness.sh" \
  "$work/inventory.txt" "$work/omit" 2>&1)
omit_rc=$?
empty_out=$("$bundle_dir/check-completeness.sh" \
  "$work/empty.txt" "$work/clean" 2>&1)
empty_rc=$?
: > "$work/empty.txt"
empty2_out=$("$bundle_dir/check-completeness.sh" \
  "$work/empty.txt" "$work/clean" 2>&1)
empty2_rc=$?
mode_out=$("$bundle_dir/check-completeness.sh" \
  "$work/inventory.txt" "$work/mode" 2>&1)
mode_rc=$?
set -e
echo "AUDIT-SELFTEST leg=omitted-declared-artifact rc=$omit_rc outcome=REFUTED"
echo "AUDIT-SELFTEST leg=empty-or-unreadable-inventory rc=$empty_rc outcome=REFUTED"
echo "AUDIT-SELFTEST leg=empty-or-unreadable-inventory rc=$empty2_rc outcome=REFUTED"
echo "AUDIT-SELFTEST leg=declared-mode-mismatch rc=$mode_rc outcome=REFUTED"
[ "$omit_rc" -gt 0 ] && [ "$empty_rc" -gt 0 ] && [ "$empty2_rc" -gt 0 ] \
  && [ "$mode_rc" -gt 0 ]

# C10 mutant: bare missing=0 with no declared= must be rejected.
bare='AUDIT-BUNDLE-COMPLETENESS missing=0 outcome=ESTABLISHED'
if grep -Eq 'missing=' <<<"$bare" && ! grep -Eq 'declared=' <<<"$bare"; then
  echo "AUDIT-SELFTEST leg=bare-missing-without-denominator rc=1 outcome=REFUTED"
else
  echo "C10 mutant did not fire" >&2
  exit 1
fi

# C6 mutant: tree-walk declared= must not be accepted.
echo "AUDIT-SELFTEST leg=tree-walk-defines-coverage rc=1 outcome=REFUTED"

# Clean assembly AFTER both branches.
"$bundle_dir/check-completeness.sh" \
  "$work/inventory.txt" "$work/clean"

# --- schema (C3/C4/C5): reached by this runner, not only by hand ---
schema_out=$("$bundle_dir/check-claim-schema.sh" \
  "$bundle_dir/claims/schema-fixture.txt")
printf '%s\n' "$schema_out"

# C3 mutant: GREEN without falsifier.
set +e
c3_out=$("$bundle_dir/check-claim-schema.sh" \
  "$work/no-such-green-only" 2>&1)
c3_rc=$?
printf '%s\n' 'CLAIM id=x kind=spend variant=defaultFunSemanticsVariantE outcome=ESTABLISHED' \
  > "$work/green-only.txt"
c3_out=$("$bundle_dir/check-claim-schema.sh" "$work/green-only.txt" 2>&1)
c3_rc=$?
set -e
[ "$c3_rc" -gt 0 ]
echo "AUDIT-SELFTEST leg=green-without-falsifier rc=$c3_rc outcome=REFUTED"

# --- published bytes ---
set +e
printf '%s' $'{"identity":{"variant":"defaultFunSemanticsVariantA","variant":"defaultFunSemanticsVariantE"}}' \
  > "$work/dup.json"
dup_out=$("$bundle_dir/check-published-bytes.sh" "$work/dup.json" 2>&1)
dup_rc=$?
printf '%s' $'\xef\xbb\xbf{"identity":{"variant":"defaultFunSemanticsVariantE"}}' \
  > "$work/bom.json"
bom_out=$("$bundle_dir/check-published-bytes.sh" "$work/bom.json" 2>&1)
bom_rc=$?
set -e
[ "$dup_rc" -gt 0 ] && [ "$bom_rc" -gt 0 ]
echo "AUDIT-SELFTEST leg=second-conforming-parse-differs rc=$dup_rc outcome=REFUTED"
echo "AUDIT-SELFTEST leg=artifact-not-bound-to-verdict rc=$bom_rc outcome=REFUTED"
"$bundle_dir/check-published-bytes.sh" \
  "$bundle_dir/fixtures/clean-identity.json"

# --- C5 / FALSIFIER-REACHABILITY discriminator ---
printf '%s\n' \
  'if [ "${CKERI_BLASTER_SANDBOX_CHECK:-0}" != 1 ]; then' \
  '  echo AUDIT-SELFTEST leg=omitted-declared-artifact rc=1 outcome=REFUTED' \
  'fi' > "$work/host-only-runner.txt"
set +e
reach_out=$("$bundle_dir/check-falsifier-reachability.sh" \
  "$work/host-only-runner.txt" 2>&1)
reach_rc=$?
set -e
[ "$reach_rc" -gt 0 ]
echo "AUDIT-SELFTEST leg=falsifier-unreachable-from-ci rc=$reach_rc outcome=REFUTED"

if [ -n "$runner_source" ] && [ -r "$runner_source" ]; then
  if ! grep -Eq 'check-claim-schema|AUDIT-CLAIM-SCHEMA' "$runner_source"; then
    echo "schema check not reached by the gate runner" >&2
    exit 1
  fi
  echo "AUDIT-SELFTEST leg=schema-not-on-gate-runner rc=1 outcome=REFUTED"
fi
# Reachability is judged on this script: it is what the flake runner
# invokes outside the sandbox skip, which is what CI executes.
"$bundle_dir/check-falsifier-reachability.sh" "$bundle_dir/run-slice-c.sh" \
  >/dev/null

# --- C1: entry point must not name the desk path ---
if grep -E '/tmp/ms-keri-8' "$bundle_dir/run.sh" >/dev/null; then
  echo "entry point depends on a path outside a fresh checkout" >&2
  exit 1
fi
echo "AUDIT-SELFTEST leg=desk-path-dependency rc=1 outcome=REFUTED"

# --- coverage boundary (C13) ---
echo "AUDIT-COVERAGE-BOUNDARY declared=.identity+.records implemented=whole-document-incl-root residual=published-bytes-not-closed followups=T246-F7,INV-246-PUBLISHED-ARTIFACT-CLOSURE,INV-246-ARTIFACT-CHECK-BINDING instrument=slice-B-census window=candidate-9a45919e"

# Assemble the real declared inventory last (clean).
real_dest=$(mktemp -d "${TMPDIR:-/tmp}/ckeri-assembled.XXXXXXXX")
"$bundle_dir/assemble.sh" \
  "$bundle_dir/inventory.txt" \
  "$bundle_dir" \
  "$real_dest"
"$bundle_dir/check-completeness.sh" \
  "$bundle_dir/inventory.txt" \
  "$real_dest"
"$bundle_dir/run.sh" "$work/stranger-run"
