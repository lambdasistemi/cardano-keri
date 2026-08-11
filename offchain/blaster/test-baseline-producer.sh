#!/usr/bin/env bash
set -euo pipefail

fail() { echo "baseline-producer-test: FAIL: $*" >&2; exit 1; }
[ "$#" -eq 5 ] || fail "usage: $0 GENERATOR CHECKER REPO_ROOT BLUEPRINT MANIFEST"
generator=$1
checker=$2
repo_root=$3
blueprint=$4
manifest=$5

for path in "$generator" "$checker"; do [ -x "$path" ] || fail "not executable: $path"; done
for path in "$blueprint" "$manifest"; do [ -r "$path" ] || fail "not readable: $path"; done

work=$(mktemp -d "${TMPDIR:-/tmp}/baseline-producer-contract.XXXXXXXX")
trap 'rm -rf "$work"' EXIT

# Every producer expectation is supplied by the caller from the flake's source
# identity, lock and inputs. Reading any of these values back out of $manifest
# would make byte comparison self-referential and unable to falsify drift.
for name in BASELINE_COMMIT BASELINE_AIKEN BASELINE_VARIANT BASELINE_ERA \
  BASELINE_VERSION_DERIVED BASELINE_TOOLCHAIN BASELINE_LOCK_SHA256 \
  BASELINE_LEAN_BLASTER_REV BASELINE_PLUTUS_CORE_REV \
  BASELINE_LEDGER_API_REV; do
  [ -n "${!name:-}" ] || fail "external producer expectation is missing: $name"
  export "$name"
done

"$generator" "$blueprint" "$work/regenerated.json"
cmp "$manifest" "$work/regenerated.json" \
  || fail "real manifest is not the generator's byte-identical output"

"$checker" \
  --repo-root "$repo_root" \
  --identity-manifest "$manifest" \
  --blueprint "$blueprint" \
  --expected-commit "$BASELINE_COMMIT" \
  --expected-aiken "$BASELINE_AIKEN" \
  --expected-variant "$BASELINE_VARIANT" \
  --expected-era "$BASELINE_ERA" \
  --expected-toolchain "$BASELINE_TOOLCHAIN" \
  --expected-lock-sha256 "$BASELINE_LOCK_SHA256" \
  --expected-lean-blaster-rev "$BASELINE_LEAN_BLASTER_REV" \
  --expected-plutus-core-rev "$BASELINE_PLUTUS_CORE_REV" \
  --expected-ledger-api-rev "$BASELINE_LEDGER_API_REV" \
  > "$work/checker.out"

expect_red() { local label=$1 expected=$2 out rc; shift 2
  set +e; out=$("$@" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "$label unexpectedly exited 0"
  [[ $out == *"$expected"* ]] || fail "$label missed diagnostic '$expected': $out"
  printf 'PRODUCER-MUTANT invariant=%s rc=%s diagnostic=%s outcome=REFUTED\n' "$label" "$rc" "$expected"
}

# B3: alter real blueprint fields, rerun the real producer, and require the
# corresponding generated field to move. A literal-emitting producer fails
# these controls even if its clean output happens to equal the expected value.
jq '.validators[0].title += "_moved"' "$blueprint" > "$work/title.json"
"$generator" "$work/title.json" "$work/title-manifest.json"
[ "$(jq -r '.programs[0].title' "$work/title-manifest.json")" != \
  "$(jq -r '.programs[0].title' "$manifest")" ] \
  || fail "INV-246-B3 title mutation did not move the produced title"

jq '(.validators[0].compiledCode) as $old |
  .validators |= map(if .compiledCode == $old then .compiledCode += "00" else . end)' \
  "$blueprint" > "$work/program.json"
"$generator" "$work/program.json" "$work/program-manifest.json"
[ "$(jq -r '.programs[0].program_sha256' "$work/program-manifest.json")" != \
  "$(jq -r '.programs[0].program_sha256' "$manifest")" ] \
  || fail "INV-246-B3 program mutation did not move the produced program hash"

jq '.validators[0].parameters = ((.validators[0].parameters // []) + [{title:"mutant"}])' \
  "$blueprint" > "$work/params.json"
"$generator" "$work/params.json" "$work/params-manifest.json"
[ "$(jq -r '.programs[0].params' "$work/params-manifest.json")" != \
  "$(jq -r '.programs[0].params' "$manifest")" ] \
  || fail "INV-246-B3 parameter mutation did not move the produced parameter count"
echo 'PRODUCER-MUTANT invariant=INV-246-B3 mutations=title,program-byte,parameters outcome=REFUTED'

jq '([.validators[].compiledCode] | unique) as $codes |
  .validators |= map(if .compiledCode == $codes[0] then .compiledCode = $codes[1] else . end)' \
  "$blueprint" > "$work/cardinality.json"
expect_red INV-246-B3-cardinality 'computed program cardinality moved' \
  "$generator" "$work/cardinality.json" "$work/cardinality-manifest.json"

# B4: the version-derived value is a separately named input and cannot be used
# as the explicit E selection.
BASELINE_VERSION_DERIVED=$BASELINE_VARIANT \
  expect_red INV-246-B4-version-derived-substitution \
    'version-derived selection cannot stand in for explicit variant' \
    "$generator" "$blueprint" "$work/variant-manifest.json"

# B1: inspect the actual Nix producer. The clean production blueprint must be
# input-addressed (no declared output hash) and depend on Aiken 1.1.23. The
# retained fixed-output derivation is the named mutant and must be rejected by
# the same predicate.
if [ "${SKIP_NIX_PRODUCER_CHECK:-0}" = 1 ]; then
  echo 'READINESS-NOTE invariant=INV-246-B1 nix-derivation inspection deferred until committed flake source'
  echo 'PASS: baseline producer fields are computed; source-build control deferred'
  exit 0
fi
flake_ref=${BASELINE_FLAKE_REF:-.}
producer_drv=$(cd "$repo_root/offchain" && nix derivation show "$flake_ref#plutus-blueprint")
jq -e 'to_entries | length == 1 and
  (.[0].value.outputs.out.hash == null) and
  ([.[0].value.inputDrvs | keys[] | select(test("aiken-1\\.1\\.23"))] | length >= 1)' \
  <<< "$producer_drv" >/dev/null \
  || fail "INV-246-B1 production blueprint is fixed-output or lacks validating Aiken 1.1.23"

mutant_drv=$(cd "$repo_root/offchain" && nix derivation show "$flake_ref#retired-m8-cold-probe")
set +e
mutant_out=$(jq -e 'to_entries | length == 1 and
  (.[0].value.outputs.out.hash == null) and
  ([.[0].value.inputDrvs | keys[] | select(test("aiken-1\\.1\\.23"))] | length >= 1)' \
  <<< "$mutant_drv" 2>&1)
mutant_rc=$?
set -e
[ "$mutant_rc" -ne 0 ] \
  || fail "INV-246-B1 fixed-output retired producer mutant satisfied source-build predicate"
echo "PRODUCER-MUTANT invariant=INV-246-B1 mutation=retired-fixed-output rc=$mutant_rc outcome=REFUTED"

echo 'PASS: baseline producer fields are computed and source-build/variant controls execute'
