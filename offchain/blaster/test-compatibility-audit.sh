#!/usr/bin/env bash
set -euo pipefail

# Permanent output contract and falsification controls for the pinned-source
# compatibility audit.  The audit executable is intentionally argument-free;
# all of its inputs are bound by the flake that builds it.

runner="${1:-}"
lock="${2:-}"
source_root="${3:-}"
seed="${4:-}"
namespace_seed="${5:-}"
nested_namespace_seed="${6:-}"
unrecognised_seed="${7:-}"
collector_seed="${8:-}"
base="${9:-}"
expected_commit="${10:-}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  printf 'test-compatibility-audit: %s\n' "$*" >&2
  exit 1
}

reference_count() {
  grep -cE '^AUDIT-REFERENCE scope=tracked .* resolved=true coverage=parsed-document outcome=ESTABLISHED$' "$1" || true
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
    grep -Eq "^AUDIT-REFERENCE scope=tracked .*reference=[^ ]*$probe .*resolved=true coverage=parsed-document outcome=ESTABLISHED$" "$out" \
      || return 1
  done
}

validate_a3() {
  local out="$1"
  grep -Eq '^AUDIT-RUN scope=tracked\+seeded-retired verdict=FAIL unresolved=[1-9][0-9]*$' "$out" || return 1
  grep -Eq '^AUDIT-REFERENCE scope=seeded-retired .*resolved=false outcome=REFUTED$' "$out" || return 1
  grep -Eq '^AUDIT-CONTROL id=[^ ]+ kind=seeded-retired-reference .*outcome=REFUTED$' "$out"
}

validate_selftests() {
  local out="$1" leg
  for leg in unresolved-in-tracked-scope namespace-move nested-namespace export-alias \
      prefix-field probe-twin synthesised-reference collector-narrowing \
      collector-closure pinned-module-graph foreign-build-root; do
    grep -Eq "^AUDIT-SELFTEST leg=$leg rc=[1-9][0-9]* outcome=REFUTED$" "$out" \
      || return 1
  done
}

validate_discovery() {
  local out="$1" commit="$2" coverage collected total instrument total_instrument
  coverage="$(grep -E '^AUDIT-COVERAGE collected=[0-9]+ total=[0-9]+ digest=[0-9a-f]{16,} classes=direct-imports,elaborated-constants instrument=[^ ]+ total_instrument=[^ ]+ window=commit:[^:]+:scope:tracked coverage=parsed-document outcome=ESTABLISHED$' "$out" || true)"
  [[ $(grep -c . <<<"$coverage" || true) -eq 1 ]] || return 1
  collected="$(sed -nE 's/^AUDIT-COVERAGE collected=([0-9]+) .*/\1/p' <<<"$coverage")"
  total="$(sed -nE 's/^AUDIT-COVERAGE collected=[0-9]+ total=([0-9]+) .*/\1/p' <<<"$coverage")"
  instrument="$(sed -nE 's/.* instrument=([^ ]+) .*/\1/p' <<<"$coverage")"
  total_instrument="$(sed -nE 's/.* total_instrument=([^ ]+) .*/\1/p' <<<"$coverage")"
  [[ $collected =~ ^[1-9][0-9]*$ && $total =~ ^[1-9][0-9]*$ ]] || return 1
  [[ $collected -eq $total ]] || return 1
  [[ -n $instrument && -n $total_instrument && $instrument != "$total_instrument" ]] \
    || return 1
  grep -Fq "window=commit:$commit:scope:tracked coverage=parsed-document outcome=ESTABLISHED" "$out" \
    || return 1
  grep -Eq '^AUDIT-SELFTEST leg=collector-closure rc=[1-9][0-9]* outcome=REFUTED$' "$out"
}

validate_oracle() {
  local out="$1"
  ! grep -Eq '^AUDIT-REFERENCE scope=tracked .* resolved=false ' "$out" \
    || return 1
  grep -Eq '^AUDIT-REFERENCE scope=selftest-nested-namespace .*reference=PlutusCore\.ByteStringInternal\.appendByteString resolved=false outcome=REFUTED$' "$out" \
    || return 1
  grep -Eq '^AUDIT-REFERENCE scope=selftest-nested-namespace .*reference=PlutusCore\.ByteString\.PlutusCore\.ByteStringInternal\.appendByteString resolved=true coverage=parsed-document outcome=ESTABLISHED$' "$out" \
    || return 1
  grep -Fxq 'AUDIT-ORACLE agreement=by-construction predicate=Lean.resolveGlobalConstCore coverage=parsed-document outcome=ESTABLISHED' "$out"
}

validate_synthesised() {
  local out="$1"
  grep -Eq '^AUDIT-REFERENCE scope=tracked .*provenance=elaborated reference=PlutusCore\.Default\.Internal\.BuiltinSemanticsVariant\.defaultFunSemanticsVariantC resolved=true coverage=parsed-document outcome=ESTABLISHED$' "$out" \
    || return 1
  ! grep -Eq '^AUDIT-REFERENCE scope=tracked .*provenance=synthesised ' "$out" \
    || return 1
  grep -Eq '^AUDIT-SELFTEST leg=synthesised-reference rc=[1-9][0-9]* outcome=REFUTED$' "$out"
}

validate_binding() {
  local out="$1"
  grep -Eq '^AUDIT-ORACLE-ROOT path=/nix/store/[a-z0-9]+-KeriBlaster-depRoot instrument=flake:keriBlasterPackage\.modRoot window=commit:[^:]+:scope:tracked coverage=parsed-document outcome=ESTABLISHED$' "$out" \
    || return 1
  grep -Eq '^AUDIT-SELFTEST leg=pinned-module-graph rc=[1-9][0-9]* outcome=REFUTED$' "$out"
}

validate_attribution() {
  grep -Fxq 'AUDIT-ATTRIBUTION agreement=by-construction predicate=collect-ilean-references/package_for_module coverage=parsed-document outcome=ESTABLISHED' "$1"
}

validate_a4() {
  local out="$1" pkg rev
  for pkg in leanBlaster plutusCoreBlaster cardanoLedgerApiBlaster; do
    rev="$(jq -er --arg n "$pkg" \
      'def direct($x): .nodes[.nodes[.root].inputs[$x]]; direct($n).locked.rev' \
      "$lock")" || return 1
    grep -Fq "AUDIT-PIN $pkg=$rev coverage=parsed-document outcome=ESTABLISHED" "$out" || return 1
  done
}

validate_a5() {
  grep -Eq '^AUDIT-VARIANT variant=defaultFunSemanticsVariantE expressible=(true|false) selection=era-based:[^ ]+( coverage=[^ ]+)? outcome=(ESTABLISHED|REFUTED)$' "$1"
}

validate_a6() {
  local out="$1" checked
  checked="$(grep -Ec '^AUDIT-(IDENTITY|PIN|REFERENCE|CONTROL|SELFTEST|VARIANT) ' "$out" || true)"
  [[ $checked -gt 0 ]] || return 1
  ! grep -E '^AUDIT-(IDENTITY|PIN|REFERENCE|CONTROL|SELFTEST|VARIANT) ' "$out" \
    | grep -Evq ' outcome=(ESTABLISHED|REFUTED|COULD-NOT-EVALUATE)( layer=[^ ]+)?$' || return 1
  ! grep -Eq '^AUDIT-.* outcome=COULD-NOT-EVALUATE( |$)' "$out"
}

validate_a7() {
  local out="$1"
  [[ $(grep -Ec '^AUDIT-CONTROL id=[^ ]+ kind=(positive-resolution|seeded-retired-reference) ' "$out") -eq 2 ]] || return 1
  [[ $(grep -Ec '^AUDIT-SELFTEST leg=(unresolved-in-tracked-scope|namespace-move) rc=[1-9][0-9]* outcome=REFUTED$' "$out") -eq 2 ]] || return 1
  grep -Fxq 'AUDIT-VERDICT PASS' "$out"
}

validate_a8() {
  [[ $1 == "$2" ]]
}

validate_a9() {
  ! grep -Eq '^offchain/blaster/KeriBlaster(\.lean|/.*\.lean)$' "$1"
}

validate_a10() {
  grep -Fq "AUDIT-IDENTITY commit=$2 coverage=parsed-document outcome=ESTABLISHED" "$1"
}

validate_a14() {
  local out="$1" commit="$2" resolved unresolved denominator leg rc
  resolved="$(sed -nE 's/^AUDIT-MEASUREMENT metric=reference-resolution resolved=([0-9]+) unresolved=([0-9]+) denominator=([0-9]+) instrument=Lean\.Environment window=commit:[^:]+:scope:tracked coverage=parsed-document outcome=ESTABLISHED$/\1/p' "$out")"
  unresolved="$(sed -nE 's/^AUDIT-MEASUREMENT metric=reference-resolution resolved=([0-9]+) unresolved=([0-9]+) denominator=([0-9]+) instrument=Lean\.Environment window=commit:[^:]+:scope:tracked coverage=parsed-document outcome=ESTABLISHED$/\2/p' "$out")"
  denominator="$(sed -nE 's/^AUDIT-MEASUREMENT metric=reference-resolution resolved=([0-9]+) unresolved=([0-9]+) denominator=([0-9]+) instrument=Lean\.Environment window=commit:[^:]+:scope:tracked coverage=parsed-document outcome=ESTABLISHED$/\3/p' "$out")"
  [[ $resolved =~ ^[0-9]+$ && $unresolved =~ ^[0-9]+$ && $denominator =~ ^[0-9]+$ ]] \
    || return 1
  [[ $((resolved + unresolved)) -eq $denominator ]] || return 1
  grep -Fq "window=commit:$commit:scope:tracked coverage=parsed-document outcome=ESTABLISHED" "$out" \
    || return 1
  grep -Eq "^AUDIT-MEASUREMENT metric=reference-resolution scope=seeded-retired resolved=[0-9]+ unresolved=[0-9]+ denominator=[0-9]+ instrument=Lean.Environment window=commit:$commit:seed:retired-reference coverage=parsed-document outcome=ESTABLISHED$" "$out" \
    || return 1
  grep -Eq "^AUDIT-COVERAGE collected=[1-9][0-9]* total=[1-9][0-9]* digest=[0-9a-f]{16,} classes=direct-imports,elaborated-constants instrument=[^ ]+ total_instrument=[^ ]+ window=commit:$commit:scope:tracked coverage=parsed-document outcome=ESTABLISHED$" "$out" \
    || return 1
  grep -Eq "^AUDIT-ORACLE-ROOT path=[^ ]+ instrument=flake:keriBlasterPackage.modRoot window=commit:$commit:scope:tracked coverage=parsed-document outcome=ESTABLISHED$" "$out" \
    || return 1
  for leg in unresolved-in-tracked-scope namespace-move nested-namespace export-alias \
      prefix-field probe-twin synthesised-reference collector-narrowing \
      collector-closure pinned-module-graph foreign-build-root; do
    rc="$(sed -nE "s/^AUDIT-SELFTEST leg=$leg rc=([1-9][0-9]*) outcome=REFUTED$/\\1/p" "$out")"
    [[ $rc =~ ^[1-9][0-9]*$ ]] || return 1
    grep -Fq "AUDIT-MEASUREMENT metric=selftest-exit-code leg=$leg value=$rc " "$out" \
      || return 1
    grep -Eq "^AUDIT-MEASUREMENT metric=selftest-exit-code leg=$leg value=$rc instrument=[^ ]+ window=commit:$commit:seed:$leg coverage=parsed-document outcome=ESTABLISHED$" "$out" \
      || return 1
  done
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
    printf 'AUDIT-IDENTITY commit=%s coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf 'AUDIT-PIN leanBlaster=%s coverage=parsed-document outcome=ESTABLISHED\n' "$lean_rev"
    printf 'AUDIT-PIN plutusCoreBlaster=%s coverage=parsed-document outcome=ESTABLISHED\n' "$plutus_rev"
    printf 'AUDIT-PIN cardanoLedgerApiBlaster=%s coverage=parsed-document outcome=ESTABLISHED\n' "$ledger_rev"
    printf '%s\n' 'AUDIT-REFERENCE scope=tracked source_path=offchain/blaster/KeriBlaster/S2Evidence.lean target_package=plutusCoreBlaster provenance=elaborated reference=PlutusCore.UPLC.BuiltinFunctions.Evaluate.evaluateBuiltinFunction resolved=true coverage=parsed-document outcome=ESTABLISHED'
    printf '%s\n' 'AUDIT-REFERENCE scope=tracked source_path=offchain/blaster/KeriBlaster/S2Cek.lean target_package=plutusCoreBlaster provenance=elaborated reference=PlutusCore.Default.Internal.BuiltinSemanticsVariant.defaultFunSemanticsVariantC resolved=true coverage=parsed-document outcome=ESTABLISHED'
    printf '%s\n' 'AUDIT-RESOLVED count=2'
    printf '%s\n' 'AUDIT-RUN scope=tracked verdict=PASS unresolved=0'
    printf '%s\n' 'AUDIT-CONTROL id=source-positive kind=positive-resolution expected=resolve observed=resolved coverage=parsed-document outcome=ESTABLISHED'
    printf '%s\n' 'AUDIT-REFERENCE scope=seeded-retired source_path=offchain/blaster/CompatibilityRetiredReference.lean target_package=plutusCoreBlaster reference=PlutusCore.UPLC.CekMachine.cekExecuteProgramWithSemanticsVariant resolved=false outcome=REFUTED'
    printf '%s\n' 'AUDIT-RUN scope=tracked+seeded-retired verdict=FAIL unresolved=1'
    printf '%s\n' 'AUDIT-CONTROL id=retired-reference kind=seeded-retired-reference expected=unresolved observed=unresolved outcome=REFUTED'
    printf '%s\n' 'AUDIT-SELFTEST leg=unresolved-in-tracked-scope rc=1 outcome=REFUTED'
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=unresolved-in-tracked-scope value=1 instrument=compatibility-audit/run_scope window=commit:%s:seed:unresolved-in-tracked-scope coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-SELFTEST leg=namespace-move rc=1 outcome=REFUTED'
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=namespace-move value=1 instrument=compatibility-audit/run_scope window=commit:%s:seed:namespace-move coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-REFERENCE scope=selftest-nested-namespace source_path=offchain/blaster/CompatibilityNestedNamespaceReference.lean target_package=plutusCoreBlaster reference=PlutusCore.ByteStringInternal.appendByteString resolved=false outcome=REFUTED'
    printf '%s\n' 'AUDIT-REFERENCE scope=selftest-nested-namespace source_path=offchain/blaster/CompatibilityNestedNamespaceReference.lean target_package=plutusCoreBlaster reference=PlutusCore.ByteString.PlutusCore.ByteStringInternal.appendByteString resolved=true coverage=parsed-document outcome=ESTABLISHED'
    printf '%s\n' 'AUDIT-SELFTEST leg=nested-namespace rc=1 outcome=REFUTED'
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=nested-namespace value=1 instrument=compatibility-audit/run_scope window=commit:%s:seed:nested-namespace coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-SELFTEST leg=export-alias rc=1 outcome=REFUTED'
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=export-alias value=1 instrument=compatibility-audit/declaration-membership window=commit:%s:seed:export-alias coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-SELFTEST leg=prefix-field rc=1 outcome=REFUTED'
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=prefix-field value=1 instrument=compatibility-audit/run_scope window=commit:%s:seed:prefix-field coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-SELFTEST leg=probe-twin rc=1 outcome=REFUTED'
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=probe-twin value=1 instrument=compatibility-audit/run_scope window=commit:%s:seed:probe-twin coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-SELFTEST leg=synthesised-reference rc=1 outcome=REFUTED'
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=synthesised-reference value=1 instrument=compatibility-audit/collector-mutation window=commit:%s:seed:synthesised-reference coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-SELFTEST leg=collector-narrowing rc=1 outcome=REFUTED'
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=collector-narrowing value=1 instrument=collect-lean-references.pl/v2 window=commit:%s:seed:collector-narrowing coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-SELFTEST leg=collector-closure rc=1 outcome=REFUTED'
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=collector-closure value=1 instrument=Lean.frontend window=commit:%s:seed:collector-closure coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-SELFTEST leg=pinned-module-graph rc=1 outcome=REFUTED'
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=pinned-module-graph value=1 instrument=compatibility-oracle/LEAN_PATH window=commit:%s:seed:pinned-module-graph coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-SELFTEST leg=foreign-build-root rc=1 outcome=REFUTED'
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=foreign-build-root value=1 instrument=source-reelaboration/root-comparison window=commit:%s:seed:foreign-build-root coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-ORACLE agreement=by-construction predicate=Lean.resolveGlobalConstCore coverage=parsed-document outcome=ESTABLISHED'
    printf 'AUDIT-ORACLE-ROOT path=/nix/store/00000000000000000000000000000000-KeriBlaster-depRoot instrument=flake:keriBlasterPackage.modRoot window=commit:%s:scope:tracked coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-VARIANT variant=defaultFunSemanticsVariantE expressible=true selection=era-based:PlutusVersion.toSemanticsVariant:postConway:selected=defaultFunSemanticsVariantE coverage=parsed-document outcome=ESTABLISHED'
    printf 'AUDIT-COVERAGE collected=2 total=2 digest=0123456789abcdef classes=direct-imports,elaborated-constants instrument=Lean.ilean/v4 total_instrument=Lean.frontend/source-reelaboration-v4 window=commit:%s:scope:tracked coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-ATTRIBUTION agreement=by-construction predicate=collect-ilean-references/package_for_module coverage=parsed-document outcome=ESTABLISHED'
    printf 'AUDIT-MEASUREMENT metric=reference-resolution resolved=2 unresolved=0 denominator=2 instrument=Lean.Environment window=commit:%s:scope:tracked coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf 'AUDIT-MEASUREMENT metric=reference-resolution scope=seeded-retired resolved=1 unresolved=1 denominator=2 instrument=Lean.Environment window=commit:%s:seed:retired-reference coverage=parsed-document outcome=ESTABLISHED\n' "$head"
    printf '%s\n' 'AUDIT-VERDICT PASS'
  } >"$good"

  sed 's/AUDIT-RESOLVED count=2/AUDIT-RESOLVED count=3/' "$good" >"$mutant"
  expect_red INV-A1 incomplete-resolution-set validate_a1 "$mutant"
  grep -v 'AUDIT-SELFTEST leg=namespace-move' "$good" >"$mutant"
  expect_red INV-A1 namespace-move-not-exercised validate_selftests "$mutant"
  sed 's/reference=PlutusCore.ByteStringInternal.appendByteString resolved=false outcome=REFUTED/reference=PlutusCore.ByteStringInternal.appendByteString resolved=true coverage=parsed-document outcome=ESTABLISHED/' "$good" >"$mutant"
  expect_red INV-A1 fabricated-nested-name-accepted validate_oracle "$mutant"
  sed 's/reference=PlutusCore.ByteString.PlutusCore.ByteStringInternal.appendByteString resolved=true coverage=parsed-document outcome=ESTABLISHED/reference=PlutusCore.ByteString.PlutusCore.ByteStringInternal.appendByteString resolved=false outcome=REFUTED/' "$good" >"$mutant"
  expect_red INV-A1 real-nested-name-rejected validate_oracle "$mutant"
  grep -v '^AUDIT-ORACLE ' "$good" >"$mutant"
  expect_red INV-A1 textual-oracle-unattested validate_oracle "$mutant"
  sed 's/agreement=by-construction predicate=Lean.resolveGlobalConstCore/agreement=elaborator rows_compared=2 disagreements=0/' "$good" >"$mutant"
  expect_red INV-A1 tautology-labelled-as-measurement validate_oracle "$mutant"
  grep -v 'AUDIT-SELFTEST leg=export-alias' "$good" >"$mutant"
  expect_red INV-246-LEAN-ENVIRONMENT declaration-membership-alias-regression validate_selftests "$mutant"
  grep -v 'AUDIT-SELFTEST leg=prefix-field' "$good" >"$mutant"
  expect_red INV-246-LEAN-ENVIRONMENT resolvable-prefix-acceptance validate_selftests "$mutant"
  grep -v 'AUDIT-SELFTEST leg=probe-twin' "$good" >"$mutant"
  expect_red INV-A2 positive-probe-without-negative-twin validate_selftests "$mutant"
  grep -v 'AUDIT-SELFTEST leg=synthesised-reference' "$good" >"$mutant"
  expect_red INV-246-SYNTHESISED-REFERENCE producer-mutation-absent validate_selftests "$mutant"
  sed 's/provenance=elaborated reference=PlutusCore.Default.Internal.BuiltinSemanticsVariant.defaultFunSemanticsVariantC/provenance=synthesised reference=PlutusCore.Default.BuiltinSemanticsVariant.defaultFunSemanticsVariantC/' "$good" >"$mutant"
  expect_red INV-246-SYNTHESISED-REFERENCE fabricated-spelling-published validate_synthesised "$mutant"
  grep -v 'AUDIT-SELFTEST leg=collector-narrowing' "$good" >"$mutant"
  expect_red INV-246-REFERENCE-DISCOVERY unrecognised-construct-narrows-denominator validate_selftests "$mutant"
  grep -v '^AUDIT-COVERAGE ' "$good" >"$mutant"
  expect_red INV-246-REFERENCE-DISCOVERY collected-count-without-provenance validate_discovery "$mutant" "$head"
  sed 's/AUDIT-COVERAGE collected=2 total=2/AUDIT-COVERAGE collected=1 total=2/' "$good" >"$mutant"
  expect_red INV-A1.v1 semantic-population-row-dropped validate_discovery "$mutant" "$head"
  grep -v 'AUDIT-SELFTEST leg=foreign-build-root' "$good" >"$mutant"
  expect_red INV-246-BUILD-ROOT-PROVENANCE foreign-build-root-control-absent validate_selftests "$mutant"
  sed 's/total_instrument=Lean.frontend\/source-reelaboration-v4/total_instrument=Lean.ilean\/v4/' "$good" >"$mutant"
  expect_red INV-246-DENOMINATOR-INSTRUMENT-DISJOINT shared-denominator-instrument validate_discovery "$mutant" "$head"
  grep -v '^AUDIT-ATTRIBUTION ' "$good" >"$mutant"
  expect_red INV-246-PACKAGE-ATTRIBUTION-AGREEMENT split-attribution-predicate validate_attribution "$mutant"
  grep -v '^AUDIT-ORACLE-ROOT ' "$good" >"$mutant"
  expect_red INV-246-RESOLUTION-CLOSURE-BINDING unnamed-oracle-root validate_binding "$mutant"
  grep -v 'AUDIT-SELFTEST leg=pinned-module-graph' "$good" >"$mutant"
  expect_red INV-246-PINNED-MODULE-GRAPH unmutated-module-graph validate_binding "$mutant"
  grep -v 'kind=positive-resolution' "$good" >"$mutant"
  expect_red INV-A2 missing-positive-control validate_a2 "$mutant"
  grep -v 'reference=.*defaultFunSemanticsVariantC ' "$good" >"$mutant"
  expect_red INV-A2 missing-required-probe validate_a2 "$mutant"
  grep -v 'scope=tracked+seeded-retired\|scope=seeded-retired\|kind=seeded-retired-reference' "$good" >"$mutant"
  expect_red INV-A3 skipped-seeded-reference validate_a3 "$mutant"
  grep -v 'AUDIT-SELFTEST leg=unresolved-in-tracked-scope' "$good" >"$mutant"
  expect_red INV-A3 failure-path-not-exercised validate_selftests "$mutant"
  sed "s/leanBlaster=$lean_rev/leanBlaster=transcribed-stale-pin/" "$good" >"$mutant"
  expect_red INV-A4 stale-pin-identity validate_a4 "$mutant"
  grep -v '^AUDIT-VARIANT ' "$good" >"$mutant"
  expect_red INV-A5 unanswered-variant validate_a5 "$mutant"
  sed 's/outcome=ESTABLISHED$/outcome=COULD-NOT-EVALUATE layer=resolver/' "$good" >"$mutant"
  expect_red INV-A6 could-not-evaluate-counted-clean validate_a6 "$mutant"
  grep -v 'kind=positive-resolution' "$good" >"$mutant"
  expect_red INV-A7 control-not-reached validate_a7 "$mutant"
  cp "$lock" "$work/lock-mutant.json"
  lock_before="$(sha256sum "$work/lock-mutant.json" | cut -d ' ' -f 1)"
  jq '.nodes.root.inputs.__slice_a2_mutant = "missing-node"' \
    "$work/lock-mutant.json" >"$work/lock-mutant.rewritten.json"
  mv "$work/lock-mutant.rewritten.json" "$work/lock-mutant.json"
  lock_after="$(sha256sum "$work/lock-mutant.json" | cut -d ' ' -f 1)"
  expect_red INV-A8 actual-lock-rewrite validate_a8 "$lock_before" "$lock_after"
  printf '%s\n' offchain/blaster/KeriBlaster.lean >"$mutant"
  expect_red INV-A9 tracked-lean-rewritten validate_a9 "$mutant"
  sed "s/commit=$head/commit=wrong-tree/" "$good" >"$mutant"
  expect_red INV-A10 unnamed-audited-tree validate_a10 "$mutant" "$head"
  grep -v '^AUDIT-MEASUREMENT ' "$good" >"$mutant"
  expect_red INV-A14 measurement-provenance-absent validate_a14 "$mutant" "$head"
}

[[ -n $lock && -f $lock ]] || fail "locked input record is unavailable: $lock"
[[ -n $source_root && -d $source_root ]] || fail "tracked source root is unavailable: $source_root"
[[ -n $seed && -f $seed ]] || fail "seeded retired-reference artefact is unavailable: $seed"
[[ -n $namespace_seed && -f $namespace_seed ]] || fail "namespace-move seed is unavailable: $namespace_seed"
[[ -n $nested_namespace_seed && -f $nested_namespace_seed ]] || fail "nested-namespace seed is unavailable: $nested_namespace_seed"
[[ -n $unrecognised_seed && -f $unrecognised_seed ]] || fail "unrecognised-syntax seed is unavailable: $unrecognised_seed"
[[ -n $collector_seed && -f $collector_seed ]] || fail "collector-closure seed is unavailable: $collector_seed"
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
grep -Fq 'PlutusCore.UPLC.CekMachine (evaluateBuiltinFunction)' "$namespace_seed" \
  || fail 'namespace-move evaluateBuiltinFunction reference is absent'
grep -Fq 'PlutusCore.Default (cekExecuteProgramWithSemanticVariant)' "$namespace_seed" \
  || fail 'namespace-move CEK reference is absent'
grep -Fq 'PlutusCore.ByteStringInternal.appendByteString' "$nested_namespace_seed" \
  || fail 'nested-namespace fabricated reference is absent'
grep -Fq 'PlutusCore.ByteString.PlutusCore.ByteStringInternal.appendByteString' "$nested_namespace_seed" \
  || fail 'nested-namespace real reference is absent'
grep -Fq 'open PlutusCore.UPLC' "$unrecognised_seed" \
  || fail 'collector-narrowing bare-open construct is absent'
grep -Fq '| .Halt _ => true' "$collector_seed" \
  || fail 'collector-closure leading-dot construct is absent'

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
validate_selftests "$work/audit.out" || fail 'INV-A1/A3 self-test failure paths were not both reached'
validate_oracle "$work/audit.out" || fail 'INV-A1 resolver is not an elaborator-backed, both-directions oracle'
validate_synthesised "$work/audit.out" \
  || fail 'INV-246-SYNTHESISED-REFERENCE provenance or spelling is invalid'
validate_discovery "$work/audit.out" "$expected_commit" \
  || fail 'INV-246-REFERENCE-DISCOVERY did not fail closed or publish its measured denominator'
validate_binding "$work/audit.out" \
  || fail 'oracle resolution is not bound to the tracked package build root'
validate_attribution "$work/audit.out" \
  || fail 'package attribution is not owned by one shared predicate'
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
validate_a14 "$work/audit.out" "$expected_commit" \
  || fail 'INV-A14 measured quantities lack instrument or measurement window'

argument_rc=0
"$runner" unexpected-argument >"$work/argument.out" 2>"$work/argument.err" \
  || argument_rc=$?
[[ $argument_rc -ne 0 ]] || fail 'compatibility audit accepted an argument'

printf '%s\n' \
  'PASS: compatibility audit resolved tracked references and executed both controls'
