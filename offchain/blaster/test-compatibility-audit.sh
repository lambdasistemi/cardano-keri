#!/usr/bin/env bash
set -euo pipefail

# Permanent output contract and falsification controls for the pinned-source
# compatibility audit.  The audit executable is intentionally argument-free;
# all of its inputs are bound by the flake that builds it.

runner="${1:-}"
lock="${2:-}"
source_root="${3:-}"
seed="${4:-}"
base="${5:-}"
expected_commit="${6:-}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  printf 'test-compatibility-audit: %s\n' "$*" >&2
  exit 1
}

reference_count() {
  grep -cE '^AUDIT-REFERENCE scope=tracked .* resolved=true outcome=ESTABLISHED$' "$1" || true
}

validate_a1() {
  local out="$1" declared observed
  grep -Eq '^AUDIT-RUN scope=tracked verdict=PASS unresolved=0$' "$out" || return 1
  ! grep -Eq '^AUDIT-REFERENCE scope=tracked .* resolved=false ' "$out" || return 1
  declared="$(sed -n 's/^AUDIT-RESOLVED count=\([0-9][0-9]*\)$/\1/p' "$out")"
  [[ $declared =~ ^[0-9]+$ ]] || return 1
  observed="$(reference_count "$out")"
  [[ $declared -eq $observed ]]
}

validate_a2() {
  local out="$1" probe
  [[ $(reference_count "$out") -gt 0 ]] || return 1
  grep -Eq '^AUDIT-CONTROL id=[^ ]+ kind=positive-resolution .*outcome=ESTABLISHED$' "$out" || return 1
  for probe in evaluateBuiltinFunction defaultFunSemanticsVariantC; do
    grep -Eq "^AUDIT-REFERENCE scope=tracked .*reference=[^ ]*$probe .*resolved=true outcome=ESTABLISHED$" "$out" \
      || return 1
  done
}

validate_a3() {
  local out="$1"
  grep -Eq '^AUDIT-RUN scope=tracked\+seeded-retired verdict=FAIL unresolved=[1-9][0-9]*$' "$out" || return 1
  grep -Eq '^AUDIT-REFERENCE scope=seeded-retired .*resolved=false outcome=REFUTED$' "$out" || return 1
  grep -Eq '^AUDIT-CONTROL id=[^ ]+ kind=seeded-retired-reference .*outcome=REFUTED$' "$out"
}

validate_a4() {
  local out="$1" pkg rev
  for pkg in leanBlaster plutusCoreBlaster cardanoLedgerApiBlaster; do
    rev="$(jq -er --arg n "$pkg" \
      'def direct($x): .nodes[.nodes[.root].inputs[$x]]; direct($n).locked.rev' \
      "$lock")" || return 1
    grep -Fq "AUDIT-PIN $pkg=$rev outcome=ESTABLISHED" "$out" || return 1
  done
}

validate_a5() {
  grep -Eq '^AUDIT-VARIANT variant=defaultFunSemanticsVariantE expressible=(true|false) selection=era-based:[^ ]+ outcome=(ESTABLISHED|REFUTED)$' "$1"
}

validate_a6() {
  local out="$1" checked
  checked="$(grep -Ec '^AUDIT-(IDENTITY|PIN|REFERENCE|CONTROL|VARIANT) ' "$out" || true)"
  [[ $checked -gt 0 ]] || return 1
  ! grep -E '^AUDIT-(IDENTITY|PIN|REFERENCE|CONTROL|VARIANT) ' "$out" \
    | grep -Evq ' outcome=(ESTABLISHED|REFUTED|COULD-NOT-EVALUATE)( layer=[^ ]+)?$' || return 1
  ! grep -Eq '^AUDIT-.* outcome=COULD-NOT-EVALUATE( |$)' "$out"
}

validate_a7() {
  local out="$1"
  [[ $(grep -Ec '^AUDIT-CONTROL id=[^ ]+ kind=(positive-resolution|seeded-retired-reference) ' "$out") -eq 2 ]] || return 1
  grep -Fxq 'AUDIT-VERDICT PASS' "$out"
}

validate_a8() {
  [[ $1 == "$2" ]]
}

validate_a9() {
  ! grep -Eq '^offchain/blaster/KeriBlaster(\.lean|/.*\.lean)$' "$1"
}

validate_a10() {
  grep -Fq "AUDIT-IDENTITY commit=$2 outcome=ESTABLISHED" "$1"
}

expect_red() {
  local invariant="$1" mutation="$2"
  shift 2
  if "$@"; then
    fail "$invariant assertion accepted mutation: $mutation"
  fi
  printf 'RED-PROOF invariant=%s mutation=%s outcome=REFUTED\n' \
    "$invariant" "$mutation"
}

prove_assertions_can_fail() {
  local good="$work/good.out" mutant="$work/mutant.out" head
  head="${expected_commit:-fixture-commit}"
  local lean_rev plutus_rev ledger_rev
  lean_rev="$(jq -er 'def direct($x): .nodes[.nodes[.root].inputs[$x]]; direct("leanBlaster").locked.rev' "$lock")"
  plutus_rev="$(jq -er 'def direct($x): .nodes[.nodes[.root].inputs[$x]]; direct("plutusCoreBlaster").locked.rev' "$lock")"
  ledger_rev="$(jq -er 'def direct($x): .nodes[.nodes[.root].inputs[$x]]; direct("cardanoLedgerApiBlaster").locked.rev' "$lock")"

  {
    printf 'AUDIT-IDENTITY commit=%s outcome=ESTABLISHED\n' "$head"
    printf 'AUDIT-PIN leanBlaster=%s outcome=ESTABLISHED\n' "$lean_rev"
    printf 'AUDIT-PIN plutusCoreBlaster=%s outcome=ESTABLISHED\n' "$plutus_rev"
    printf 'AUDIT-PIN cardanoLedgerApiBlaster=%s outcome=ESTABLISHED\n' "$ledger_rev"
    printf '%s\n' 'AUDIT-REFERENCE scope=tracked source_path=offchain/blaster/KeriBlaster/S2Evidence.lean target_package=plutusCoreBlaster reference=PlutusCore.UPLC.BuiltinFunctions.Evaluate.evaluateBuiltinFunction resolved=true outcome=ESTABLISHED'
    printf '%s\n' 'AUDIT-REFERENCE scope=tracked source_path=offchain/blaster/KeriBlaster/S2Cek.lean target_package=plutusCoreBlaster reference=PlutusCore.Default.BuiltinSemanticsVariant.defaultFunSemanticsVariantC resolved=true outcome=ESTABLISHED'
    printf '%s\n' 'AUDIT-RESOLVED count=2'
    printf '%s\n' 'AUDIT-RUN scope=tracked verdict=PASS unresolved=0'
    printf '%s\n' 'AUDIT-CONTROL id=source-positive kind=positive-resolution expected=resolve observed=resolved outcome=ESTABLISHED'
    printf '%s\n' 'AUDIT-REFERENCE scope=seeded-retired source_path=offchain/blaster/CompatibilityRetiredReference.lean target_package=plutusCoreBlaster reference=PlutusCore.UPLC.CekMachine.cekExecuteProgramWithSemanticsVariant resolved=false outcome=REFUTED'
    printf '%s\n' 'AUDIT-RUN scope=tracked+seeded-retired verdict=FAIL unresolved=1'
    printf '%s\n' 'AUDIT-CONTROL id=retired-reference kind=seeded-retired-reference expected=unresolved observed=unresolved outcome=REFUTED'
    printf '%s\n' 'AUDIT-VARIANT variant=defaultFunSemanticsVariantE expressible=true selection=era-based:PlutusVersion.toSemanticsVariant:postConway:selected=defaultFunSemanticsVariantE outcome=ESTABLISHED'
    printf '%s\n' 'AUDIT-VERDICT PASS'
  } >"$good"

  sed 's/AUDIT-RESOLVED count=2/AUDIT-RESOLVED count=3/' "$good" >"$mutant"
  expect_red INV-A1 incomplete-resolution-set validate_a1 "$mutant"
  grep -v 'kind=positive-resolution' "$good" >"$mutant"
  expect_red INV-A2 missing-positive-control validate_a2 "$mutant"
  grep -v 'reference=.*defaultFunSemanticsVariantC ' "$good" >"$mutant"
  expect_red INV-A2 missing-required-probe validate_a2 "$mutant"
  grep -v 'scope=tracked+seeded-retired\|scope=seeded-retired\|kind=seeded-retired-reference' "$good" >"$mutant"
  expect_red INV-A3 skipped-seeded-reference validate_a3 "$mutant"
  sed "s/leanBlaster=$lean_rev/leanBlaster=transcribed-stale-pin/" "$good" >"$mutant"
  expect_red INV-A4 stale-pin-identity validate_a4 "$mutant"
  grep -v '^AUDIT-VARIANT ' "$good" >"$mutant"
  expect_red INV-A5 unanswered-variant validate_a5 "$mutant"
  sed 's/outcome=ESTABLISHED$/outcome=COULD-NOT-EVALUATE layer=resolver/' "$good" >"$mutant"
  expect_red INV-A6 could-not-evaluate-counted-clean validate_a6 "$mutant"
  grep -v 'kind=positive-resolution' "$good" >"$mutant"
  expect_red INV-A7 control-not-reached validate_a7 "$mutant"
  expect_red INV-A8 lock-mutated validate_a8 before after
  printf '%s\n' offchain/blaster/KeriBlaster.lean >"$mutant"
  expect_red INV-A9 tracked-lean-rewritten validate_a9 "$mutant"
  sed "s/commit=$head/commit=wrong-tree/" "$good" >"$mutant"
  expect_red INV-A10 unnamed-audited-tree validate_a10 "$mutant" "$head"
}

[[ -n $lock && -f $lock ]] || fail "locked input record is unavailable: $lock"
[[ -n $source_root && -d $source_root ]] || fail "tracked source root is unavailable: $source_root"
[[ -n $seed && -f $seed ]] || fail "seeded retired-reference artefact is unavailable: $seed"
[[ -n $base ]] || fail 'pre-slice base was not provided'

# First prove each assertion independently rejects the defect it names.  These
# controls run before the real target, so an absent runner cannot make a dead
# contract look successfully falsified.
prove_assertions_can_fail

changed_lean="$work/changed-lean"
repo_root=''
if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  git -C "$repo_root" diff --name-only "$base" -- \
    offchain/blaster/KeriBlaster.lean offchain/blaster/KeriBlaster \
    >"$changed_lean"
  [[ -n $expected_commit ]] || expected_commit="$(git -C "$repo_root" rev-parse HEAD)"
else
  : >"$changed_lean"
fi
validate_a9 "$changed_lean" || fail 'INV-A9: tracked Lean bridge source changed'
[[ -n $expected_commit ]] || fail 'expected audited commit is unavailable'

for probe in evaluateBuiltinFunction defaultFunSemanticsVariantC; do
  grep -Rq "$probe" "$source_root/KeriBlaster.lean" "$source_root/KeriBlaster" \
    || fail "positive source reference is absent: $probe"
done
grep -Fq 'cekExecuteProgramWithSemanticsVariant' "$seed" \
  || fail 'seeded retired reference is absent from its artefact'

if [[ ! -x $runner ]]; then
  printf 'RED: compatibility audit executable absent after live contract controls: %s\n' \
    "$runner" >&2
  exit 68
fi

before_lock="$(sha256sum "$lock" | cut -d ' ' -f 1)"
before_worktree_lock=''
if [[ -n $repo_root ]]; then
  before_worktree_lock="$(sha256sum "$repo_root/offchain/flake.lock" | cut -d ' ' -f 1)"
fi
"$runner" | tee "$work/audit.out"
after_lock="$(sha256sum "$lock" | cut -d ' ' -f 1)"

validate_a1 "$work/audit.out" || fail 'INV-A1 resolution set is incomplete'
validate_a2 "$work/audit.out" || fail 'INV-A2 positive resolution control failed'
validate_a3 "$work/audit.out" || fail 'INV-A3 retired-reference control failed'
validate_a4 "$work/audit.out" || fail 'INV-A4 pin identity does not match the lock'
validate_a5 "$work/audit.out" || fail 'INV-A5 variant answer is absent'
validate_a6 "$work/audit.out" || fail 'INV-A6 outcome discipline failed'
validate_a7 "$work/audit.out" || fail 'INV-A7 controls were not both reached'
validate_a8 "$before_lock" "$after_lock" || fail 'INV-A8 audit mutated flake.lock'
if [[ -n $repo_root ]]; then
  after_worktree_lock="$(sha256sum "$repo_root/offchain/flake.lock" | cut -d ' ' -f 1)"
  validate_a8 "$before_worktree_lock" "$after_worktree_lock" \
    || fail 'INV-A8 audit mutated the checkout lock'
fi
validate_a10 "$work/audit.out" "$expected_commit" \
  || fail 'INV-A10 audit identity does not name HEAD'

argument_rc=0
"$runner" unexpected-argument >"$work/argument.out" 2>"$work/argument.err" \
  || argument_rc=$?
[[ $argument_rc -ne 0 ]] || fail 'compatibility audit accepted an argument'

printf '%s\n' \
  'PASS: compatibility audit resolved tracked references and executed both controls'
