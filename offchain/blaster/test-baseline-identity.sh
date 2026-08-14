#!/usr/bin/env bash
set -euo pipefail

fail() { echo "baseline-identity-test: FAIL: $*" >&2; exit 1; }

if [ "$#" -ne 4 ]; then
  fail "usage: $0 CHECKER REPO_ROOT RETAINED_RECEIPT RETAINED_LOG"
fi

checker=$1
repo_root=$2
retained_receipt=$3
retained_log=$4
commit=4e840934deeb55aa9fd45a34fc516bb4c635bf81
aiken=1.1.23
variant=defaultFunSemanticsVariantE
era=post-Conway
selection=explicit-era-binding
version_derived=defaultFunSemanticsVariantC
verification_receipt=fixture-clean
toolchain='aiken=1.1.23;lean-blaster=62d2d59abda37e90097e655b40e27545bba16f3c;plutus-core-blaster=7cf5a78c54b9694ef093bf49edb5d3799b2a49c9;cardano-ledger-api-blaster=577e3eb03b5be09354cfdb1c0d0c12e9e16541a0'
lock_sha=96f9405089d9a28b305fae4fff9e657ec8363a157c326bcc66c3e232b8f92200
lean_blaster_rev=62d2d59abda37e90097e655b40e27545bba16f3c
plutus_core_rev=7cf5a78c54b9694ef093bf49edb5d3799b2a49c9
ledger_api_rev=577e3eb03b5be09354cfdb1c0d0c12e9e16541a0
receipt_sha=e747878a9a84bfcb3c871084c93648c54dadaf59b25509ab3403d37da999e69c
log_sha=6a0459158505243ac6eb3451d08240c47977338d4b558ee93562908cd402b3e6

[ -x "$checker" ] || fail "checker is not executable: $checker"
[ -d "$repo_root" ] || fail "repository root is absent: $repo_root"
[ -r "$retained_receipt" ] || fail "retained receipt is absent: $retained_receipt"
[ -r "$retained_log" ] || fail "retained log is absent: $retained_log"

work=$(mktemp -d "${TMPDIR:-/tmp}/baseline-identity-contract.XXXXXXXX")
trap 'rm -rf "$work"' EXIT

# Twenty-three titles over eight distinct programs. The fixture deliberately
# repeats program bytes: title cardinality and program cardinality are separate
# claims, exactly as they are in the production Aiken blueprint.
jq -n '{
  validators: [range(0; 23) as $i | {
    title: ("fixture.validator." + ($i | tostring)),
    parameters: [range(0; ($i % 4)) | {name: ("p" + (. | tostring))}],
    compiledCode: (["00", "01", "02", "03", "04", "05", "06", "07"][$i % 8])
  }]
}' > "$work/blueprint.json"

blueprint_sha=$(sha256sum "$work/blueprint.json" | cut -d ' ' -f 1)
: > "$work/programs.jsonl"
while IFS=$'\t' read -r title params code; do
  program_sha=$(printf '%s' "$code" | sha256sum | cut -d ' ' -f 1)
  jq -cn --arg title "$title" --argjson params "$params" \
    --arg program_sha256 "$program_sha" \
    '{title:$title, params:$params, program_sha256:$program_sha256,
      programHash:$program_sha256, compiledCodeHash:$program_sha256}' \
    >> "$work/programs.jsonl"
done < <(jq -r '.validators[] | [.title, ((.parameters // []) | length), .compiledCode] | @tsv' "$work/blueprint.json")
jq -s . "$work/programs.jsonl" > "$work/programs.json"

jq -n \
  --arg commit "$commit" \
  --arg aiken "$aiken" \
  --arg toolchain "$toolchain" \
  --arg variant "$variant" \
  --arg era "$era" \
  --arg selection "$selection" \
  --arg version_derived "$version_derived" \
  --arg verification_receipt "$verification_receipt" \
  --arg lock_sha256 "$lock_sha" \
  --arg lean_blaster "$lean_blaster_rev" \
  --arg plutus_core "$plutus_core_rev" \
  --arg ledger_api "$ledger_api_rev" \
  --arg blueprint_sha256 "$blueprint_sha" \
  --slurpfile programs "$work/programs.json" '
  def identity: {
    commit:$commit, aiken:$aiken, toolchain:$toolchain, variant:$variant,
    ledger_language:"PlutusV3", era:$era,
    blueprint_sha256:$blueprint_sha256
  };
  ($programs[0]) as $ps |
  {
    schema:"cardano-keri-baseline-v1",
    identity:(identity + {
      built_from:"source",
      validating_aiken:$aiken,
      selection:$selection,
      version_derived:$version_derived,
      lock_sha256:$lock_sha256,
      upstream:{lean_blaster:$lean_blaster,
        plutus_core_blaster:$plutus_core,
        cardano_ledger_api_blaster:$ledger_api}
    }),
    blueprint_sha256:$blueprint_sha256,
    programs:$ps,
    records: [$ps[] | identity + {record:"program", title:.title,
      params:.params, program_sha256:.program_sha256,
      programHash:.programHash, compiledCodeHash:.compiledCodeHash}]
  }' > "$work/manifest.json"

identity_args=(
  --repo-root "$repo_root"
  --identity-manifest "$work/manifest.json"
  --blueprint "$work/blueprint.json"
  --expected-commit "$commit"
  --expected-aiken "$aiken"
  --expected-variant "$variant"
  --expected-era "$era"
  --expected-toolchain "$toolchain"
  --expected-lock-sha256 "$lock_sha"
  --expected-lean-blaster-rev "$lean_blaster_rev"
  --expected-plutus-core-rev "$plutus_core_rev"
  --expected-ledger-api-rev "$ledger_api_rev"
)

# These expectations are caller inputs, never values read back from the
# manifest under test. Keep the RED bundle runnable against the rejected
# checker, which predates the three options, while requiring the repaired
# checker to expose and consume all three before the bundle can pass.
checker_help=$($checker --help)
coverage_expectation_options=0
if grep -Fq -- '--expected-selection' <<< "$checker_help" &&
   grep -Fq -- '--expected-version-derived' <<< "$checker_help" &&
   grep -Fq -- '--expected-verification-receipt' <<< "$checker_help"; then
  identity_args+=(
    --expected-selection "$selection"
    --expected-version-derived "$version_derived"
    --expected-verification-receipt "$verification_receipt"
  )
  coverage_expectation_options=3
fi

run_identity() { "$checker" "${identity_args[@]}"; }

expect_red() { # label expected-diagnostic command...
  local label=$1 expected=$2 out rc
  shift 2
  set +e; out=$("$@" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "$label unexpectedly exited 0"
  [[ $out == *"$expected"* ]] \
    || fail "$label exited $rc without naming '$expected': $out"
  last_red_rc=$rc
  printf 'RED-PROOF invariant=%s rc=%s diagnostic=%s outcome=REFUTED\n' \
    "$label" "$rc" "$expected"
}

expect_red_identity_copy() { # label jq-filter expected-diagnostic
  local label=$1 filter=$2 expected=$3
  jq "$filter" "$work/manifest.json" > "$work/mutant.json"
  local saved=${identity_args[3]}
  identity_args[3]="$work/mutant.json"
  expect_red "$label" "$expected" run_identity
  identity_args[3]=$saved
}

# The unmodified fixture is the positive control. It also requires the checker
# to publish a non-vacuous denominator over every current title record.
clean_out=$(run_identity 2>&1) \
  || fail "clean identity manifest was rejected: $clean_out"
grep -Fq 'CBIC_IDENTITY_RESULT records_checked=23' <<< "$clean_out" \
  || fail "clean identity result did not publish records_checked=23"
grep -Fq 'CBIC_IDENTITY_RESULT inconsistent=0' <<< "$clean_out" \
  || fail "clean identity result did not publish inconsistent=0"

clean_fields=$(sed -n 's/^CBIC_IDENTITY_RESULT fields=//p' <<< "$clean_out")
clean_reconciled=$(sed -n 's/^CBIC_IDENTITY_RESULT reconciled=//p' <<< "$clean_out")
clean_containers=$(sed -n 's/^CBIC_IDENTITY_RESULT containers=//p' <<< "$clean_out")
[ -n "$clean_fields" ] && [ "$clean_reconciled" = "$clean_fields" ] \
  && [ -n "$clean_containers" ] \
  || fail "clean identity result omitted its derived coverage denominator"

# Audit property classes. Exercise every reported survivor and aggregate the
# results so one surviving instance cannot hide another. The field-count
# control adds a scalar field without changing the title-record inventory: an
# enumeration over the complete manifest must move by one, while the
# independently built expectation population remains at its clean value.
coverage_failures=0
coverage_rc=0
last_coverage_red_rc=0
coverage_expect_red_identity_copy() { # label jq-filter expected-diagnostic
  local label=$1 filter=$2 expected=$3 out rc
  last_coverage_red_rc=0
  jq "$filter" "$work/manifest.json" > "$work/coverage-mutant.json"
  cmp -s "$work/manifest.json" "$work/coverage-mutant.json" &&
    fail "$label mutation did not apply"
  local saved=${identity_args[3]}
  identity_args[3]="$work/coverage-mutant.json"
  set +e; out=$(run_identity 2>&1); rc=$?; set -e
  identity_args[3]=$saved
  if [ "$rc" -ne 0 ] && [[ $out == *"$expected"* ]]; then
    [ "$coverage_rc" -ne 0 ] || coverage_rc=$rc
    last_coverage_red_rc=$rc
    printf 'RED-PROOF invariant=%s rc=%s diagnostic=%s outcome=REFUTED\n' \
      "$label" "$rc" "$expected"
  else
    coverage_failures=$((coverage_failures + 1))
    printf 'COVERAGE-RED-FAIL invariant=%s rc=%s expected=%s\n' \
      "$label" "$rc" "$expected" >&2
    printf '%s\n' "$out" | sed 's/^/    [checker] /' >&2
  fi
}

if [ "$coverage_expectation_options" -ne 3 ]; then
  coverage_failures=$((coverage_failures + 1))
  echo 'COVERAGE-RED-FAIL checker does not expose all three caller-supplied expectation options' >&2
fi

coverage_expect_red_identity_copy INV-246-B5-selection \
  '.identity.selection = "version-derived"' \
  'identity input moved: selection'
coverage_expect_red_identity_copy INV-246-B5-version-derived \
  '.identity.version_derived = "defaultFunSemanticsVariantA"' \
  'identity input moved: version_derived'
coverage_expect_red_identity_copy INV-246-B5-verification-receipt \
  '.records[-1].compiledCodeHash = ("f" * 64)' \
  'inconsistent identity input: compiledCodeHash'

if [ "$coverage_rc" -ne 0 ]; then
  printf 'REPAIR-SELFTEST leg=carried-field-without-reconciled-expectation rc=%s outcome=REFUTED\n' \
    "$coverage_rc"
fi

jq '.identity.unregistered_identity = "same-record-count-mutant"' \
  "$work/manifest.json" > "$work/coverage-count-mutant.json"
cmp -s "$work/manifest.json" "$work/coverage-count-mutant.json" &&
  fail 'coverage-count mutation did not apply'
saved=${identity_args[3]}
identity_args[3]="$work/coverage-count-mutant.json"
set +e; coverage_count_out=$(run_identity 2>&1); coverage_count_rc=$?; set -e
identity_args[3]=$saved
mutant_fields=$((clean_fields + 1))
if [ "$coverage_count_rc" -ne 0 ] &&
   [[ $coverage_count_out == *'COULD-NOT-EVALUATE: identity field lacks reconciled expectation: identity.unregistered_identity'* ]] &&
   grep -Fq "CBIC_IDENTITY_RESULT fields=$mutant_fields" <<< "$coverage_count_out" &&
   grep -Fq "CBIC_IDENTITY_RESULT reconciled=$clean_fields" <<< "$coverage_count_out" &&
   grep -Fq 'CBIC_IDENTITY_RESULT unexpected=1' <<< "$coverage_count_out"; then
  printf 'REPAIR-SELFTEST leg=coverage-count-not-enumerated rc=%s outcome=REFUTED\n' \
    "$coverage_count_rc"
else
  coverage_failures=$((coverage_failures + 1))
  echo "COVERAGE-RED-FAIL count control did not enumerate $mutant_fields carried fields with one unreconciled expectation" >&2
  printf '%s\n' "$coverage_count_out" | sed 's/^/    [checker] /' >&2
fi

# Release property class: a future container anywhere in the manifest must be
# covered without adding its path to a hand-maintained list. An empty nested
# object has no scalar descendant, so only the structural registry can see it.
coverage_expect_red_identity_copy INV-246-IDENTITY-FIELD-EXPECTATION-DISJOINT-container \
  '.audit_container = {nested:{}}' \
  'COULD-NOT-EVALUATE: manifest container lacks structural expectation: audit_container'
if [ "$last_coverage_red_rc" -ne 0 ]; then
  printf 'REPAIR-SELFTEST leg=unenumerated-container rc=%s outcome=REFUTED\n' \
    "$last_coverage_red_rc"
fi

# Named red condition from A-e190-018. This is also a scalar-field closure
# control over the manifest object itself, outside .identity and .records.
coverage_expect_red_identity_copy INV-246-IDENTITY-FIELD-EXPECTATION-DISJOINT-top-level-variant \
  '.variant = "defaultFunSemanticsVariantA"' \
  'COULD-NOT-EVALUATE: identity field lacks reconciled expectation: variant'
if [ "$last_coverage_red_rc" -ne 0 ]; then
  printf 'REPAIR-SELFTEST leg=top-level-variant-contradiction rc=%s outcome=REFUTED\n' \
    "$last_coverage_red_rc"
fi

# The path registry is C-sorted, so every comparison must use that same
# collation. An uppercase addition is deliberately ordered differently by the
# host UTF-8 locale; it must still reach the named checker diagnostic.
jq '.identity.NEWFIELD = "locale-mutant"' \
  "$work/manifest.json" > "$work/collation-mutant.json"
cmp -s "$work/manifest.json" "$work/collation-mutant.json" &&
  fail 'collation mutation did not apply'
saved=${identity_args[3]}
identity_args[3]="$work/collation-mutant.json"
set +e; collation_out=$(LC_ALL=en_GB.utf8 run_identity 2>&1); collation_rc=$?; set -e
identity_args[3]=$saved
if [ "$collation_rc" -ne 0 ] &&
   [[ $collation_out == *'COULD-NOT-EVALUATE: identity field lacks reconciled expectation: identity.NEWFIELD'* ]] &&
   [[ $collation_out != *'comm:'* ]]; then
  printf 'REPAIR-SELFTEST leg=collation-deterministic-comparison rc=%s outcome=REFUTED\n' \
    "$collation_rc"
else
  coverage_failures=$((coverage_failures + 1))
  echo 'COVERAGE-RED-FAIL locale control did not reach the named field diagnostic deterministically' >&2
  printf '%s\n' "$collation_out" | sed 's/^/    [checker] /' >&2
fi

for result in \
  "fields=$clean_fields" \
  "reconciled=$clean_fields" \
  'unexpected=0' \
  "containers=$clean_containers" \
  'uncovered_containers=0' \
  'enumerated_by=jq-leaf-and-container-paths'; do
  if ! grep -Fq "CBIC_IDENTITY_RESULT $result" <<< "$clean_out"; then
    coverage_failures=$((coverage_failures + 1))
    echo "COVERAGE-RED-FAIL clean result did not publish $result" >&2
  fi
done

[ "$coverage_failures" -eq 0 ] \
  || fail "$coverage_failures identity-field coverage property leg(s) remain RED"

# Every manifest input class moves independently and must be named.
expect_red_identity_copy INV-246-B5-title \
  '.programs[0].title = "fixture.validator.moved"' \
  'manifest input moved: title'
expect_red_identity_copy INV-246-B5-program \
  '.programs[0].program_sha256 = ("f" * 64)' \
  'manifest input moved: program_sha256'
expect_red_identity_copy INV-246-B5-blueprint \
  '.blueprint_sha256 = ("e" * 64)' \
  'manifest input moved: blueprint_sha256'
expect_red_identity_copy INV-246-B5-toolchain \
  '.identity.aiken = "0.0.0"' \
  'identity input moved: aiken'
expect_red_identity_copy INV-246-B5-variant \
  '.identity.variant = "defaultFunSemanticsVariantC"' \
  'identity input moved: variant'

# Missing and mutually inconsistent triple elements are distinct RED classes.
expect_red_identity_copy INV-246-B7-unnamed-commit \
  'del(.records[0].commit)' 'unnamed identity input: commit'
expect_red_identity_copy INV-246-B7-unnamed-toolchain \
  'del(.records[0].aiken)' 'unnamed identity input: aiken'
expect_red_identity_copy INV-246-B7-unnamed-variant \
  'del(.records[0].variant)' 'unnamed identity input: variant'
expect_red_identity_copy INV-246-B7-inconsistent-receipt \
  '.records[-1].commit = ("d" * 40)' 'inconsistent identity input: commit'

# Audit submission 1 repair classes. These use the producer's complete record
# shape, including the verification receipt, and each control must first prove
# its mutation can make the canonical checker fail.
expect_red_identity_copy INV-246-B7-record-toolchain-mutated \
  '.records[3].toolchain = "aiken=0.0.0"' \
  'inconsistent identity input: toolchain'
printf 'REPAIR-SELFTEST leg=record-toolchain-mutated rc=%s outcome=REFUTED\n' "$last_red_rc"

expect_red_identity_copy INV-246-IDENTITY-FIELD-EXPECTATION-DISJOINT \
  '.identity.unregistered_identity = "has-no-external-expectation"' \
  'externally-unexpected field set'
printf 'REPAIR-SELFTEST leg=identity-field-without-external-expectation rc=%s outcome=REFUTED\n' "$last_red_rc"

expect_red_identity_copy INV-246-CONTROL-SCHEMA-PRODUCTION \
  'del(.identity.toolchain) | .records |= map(del(.toolchain))' \
  'identity schema moved'
printf 'REPAIR-SELFTEST leg=control-schema-narrower-than-production rc=%s outcome=REFUTED\n' "$last_red_rc"

expect_red_identity_copy INV-246-B1-COMMIT-AUTHORITY \
  '("0" * 40) as $commit | .identity.commit = $commit |
    .records |= map(.commit = $commit)' \
  'identity input moved: commit'
printf 'REPAIR-SELFTEST leg=baseline-commit-authority-substituted rc=%s outcome=REFUTED\n' "$last_red_rc"

# Full-population schema reliance: these mutants alter the blueprint, not the
# manifest, and must fail for their schema class before a hash mismatch can
# obscure the defect.
for spec in \
  'duplicate-title|.validators[1].title = .validators[0].title|blueprint schema: duplicate title' \
  'malformed-compiledCode|.validators[4].compiledCode = 7|blueprint schema: compiledCode' \
  'non-array-parameters|.validators[8].parameters = {}|blueprint schema: parameters'
do
  IFS='|' read -r label filter expected <<< "$spec"
  jq "$filter" "$work/blueprint.json" > "$work/blueprint-mutant.json"
  saved=${identity_args[5]}
  identity_args[5]="$work/blueprint-mutant.json"
  expect_red "INV-246-BLUEPRINT-SCHEMA-$label" "$expected" run_identity
  identity_args[5]=$saved
done

# The real retained measurement must be authenticated before it is rejected.
receipt_args=(
  --repo-root "$repo_root"
  --retained-receipt "$retained_receipt"
  --retained-log "$retained_log"
  --expected-receipt-sha256 "$receipt_sha"
  --expected-log-sha256 "$log_sha"
  --expected-commit "$commit"
  --expected-aiken "$aiken"
  --expected-variant "$variant"
  --expected-era "$era"
)
set +e; retained_out=$("$checker" "${receipt_args[@]}" 2>&1); retained_rc=$?; set -e
[ "$retained_rc" -ne 0 ] || fail "retained inconsistent receipt unexpectedly passed"
for expected in 'inconsistent identity input: commit' \
                'inconsistent identity input: aiken' \
                'unnamed identity input: variant'; do
  [[ $retained_out == *"$expected"* ]] \
    || fail "retained receipt rejection did not name '$expected': $retained_out"
done
printf 'RED-PROOF invariant=INV-246-B8 mutation=retained-red-receipt rc=%s outcome=REFUTED\n' "$retained_rc"

cp "$retained_receipt" "$work/altered-receipt.md"
printf '\nbyte-altered-control\n' >> "$work/altered-receipt.md"
altered_args=("${receipt_args[@]}")
altered_args[3]="$work/altered-receipt.md"
expect_red INV-246-RETAINED-RECEIPT-IDENTITY \
  'retained receipt digest moved' "$checker" "${altered_args[@]}"

# The normal checker owns the two non-artifact identity axes: all three
# repository owners must name the validating Aiken pin, and old C bytes must
# remain explicitly historical rather than being relabelled as E.
normal_out=$("$checker" --repo-root "$repo_root" 2>&1) \
  || fail "normal identity check rejected the clean repository: $normal_out"
grep -Fq 'CBIC_RESULT validating_aiken_pins=3' <<< "$normal_out" \
  || fail "normal check did not publish validating_aiken_pins=3"
grep -Fq 'CBIC_RESULT historical_c_records=1' <<< "$normal_out" \
  || fail "normal check did not publish historical_c_records=1"

mkdir -p "$work/repo/offchain" "$work/repo/scripts" \
  "$work/repo/docs/architecture" "$work/repo/.github/workflows"
cp "$repo_root/offchain/flake.nix" "$work/repo/offchain/flake.nix"
cp "$repo_root/offchain/flake.lock" "$work/repo/offchain/flake.lock"
cp "$repo_root/justfile" "$work/repo/justfile"
cp "$repo_root/.github/workflows/ci.yml" "$work/repo/.github/workflows/ci.yml"
cp "$repo_root/docs/architecture/blaster-tractability.md" \
  "$work/repo/docs/architecture/blaster-tractability.md"

sed -i '0,/753cc8a3a87467296ddd1fa93f0cc3e81120ee46/s//0000000000000000000000000000000000000000/' \
  "$work/repo/justfile"
expect_red INV-246-VALIDATING-AIKEN-PIN \
  'validating Aiken pin moved: justfile' \
  "$checker" --repo-root "$work/repo"
cp "$repo_root/justfile" "$work/repo/justfile"

sed -i '0,/defaultFunSemanticsVariantC/s//defaultFunSemanticsVariantE/' \
  "$work/repo/docs/architecture/blaster-tractability.md"
expect_red INV-246-B6-historical-c-relabel \
  'historical C material relabelled' \
  "$checker" --repo-root "$work/repo"

echo 'PASS: baseline identity contract executed clean and falsifying controls'
