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
    '{title:$title, params:$params, program_sha256:$program_sha256}' \
    >> "$work/programs.jsonl"
done < <(jq -r '.validators[] | [.title, ((.parameters // []) | length), .compiledCode] | @tsv' "$work/blueprint.json")
jq -s . "$work/programs.jsonl" > "$work/programs.json"

jq -n \
  --arg commit "$commit" \
  --arg aiken "$aiken" \
  --arg toolchain "$toolchain" \
  --arg variant "$variant" \
  --arg era "$era" \
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
      selection:"explicit-era-binding",
      version_derived:"defaultFunSemanticsVariantC",
      lock_sha256:$lock_sha256,
      upstream:{lean_blaster:$lean_blaster,
        plutus_core_blaster:$plutus_core,
        cardano_ledger_api_blaster:$ledger_api}
    }),
    blueprint_sha256:$blueprint_sha256,
    programs:$ps,
    records: (
      [(identity + {record:"manifest"})]
      + [$ps[] | identity + {record:"program", title:.title,
          params:.params, program_sha256:.program_sha256}]
      + [
          (identity + {record:"baseline"}),
          (identity + {record:"evaluation-identity"}),
          (identity + {record:"verification-receipt", receipt:"fixture-clean"})
        ]
    )
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
# to publish a non-vacuous denominator over every carried record, receipts
# included (1 manifest + 23 programs + baseline + evaluation + receipt = 27).
clean_out=$(run_identity 2>&1) \
  || fail "clean identity manifest was rejected: $clean_out"
grep -Fq 'CBIC_IDENTITY_RESULT records_checked=27' <<< "$clean_out" \
  || fail "clean identity result did not publish records_checked=27"
grep -Fq 'CBIC_IDENTITY_RESULT inconsistent=0' <<< "$clean_out" \
  || fail "clean identity result did not publish inconsistent=0"
grep -Fq 'CBIC_IDENTITY_RESULT identity_fields=204' <<< "$clean_out" \
  || fail "clean identity result did not publish the production field denominator"
grep -Fq 'CBIC_IDENTITY_RESULT externally_expected=204' <<< "$clean_out" \
  || fail "clean identity result did not externally expect every identity field"
grep -Fq 'CBIC_IDENTITY_RESULT unexpected=0' <<< "$clean_out" \
  || fail "clean identity result did not reject fields outside the expectation registry"

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
