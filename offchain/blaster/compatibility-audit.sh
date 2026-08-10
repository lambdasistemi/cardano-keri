#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  echo 'compatibility-audit: accepts no arguments' >&2
  exit 64
fi

required_env=(
  AUDIT_COMMIT AUDIT_COLLECTOR AUDIT_ORACLE AUDIT_SOURCE_ROOT AUDIT_SEED
  AUDIT_NAMESPACE_SEED AUDIT_NESTED_NAMESPACE_SEED AUDIT_UNRECOGNISED_SEED
  AUDIT_PLUTUS_CORE_ROOT
  AUDIT_LEAN_BLASTER_REV AUDIT_PLUTUS_CORE_REV AUDIT_LEDGER_API_REV
  AUDIT_TRACKED_BUILD
)
for name in "${required_env[@]}"; do
  if [[ -z ${!name:-} ]]; then
    printf 'AUDIT-IDENTITY commit=unknown outcome=COULD-NOT-EVALUATE layer=configuration\n'
    printf 'AUDIT-VERDICT FAIL\n'
    printf 'compatibility-audit: required environment is absent: %s\n' "$name" >&2
    exit 1
  fi
done

collect() {
  "$AUDIT_COLLECTOR" "$AUDIT_SOURCE_ROOT" "$@"
}

emit_records() {
  local scope="$1" records="$2" mode="${3:-elaborator}"
  local resolved_records="$work/resolved-$scope.tsv"
  local source package reference kind resolution
  local resolved=0 unresolved=0
  local -a oracle_args=("$records")
  if [[ $mode == declaration-membership ]]; then
    oracle_args=(--declaration-membership "$records")
  fi
  if ! "$AUDIT_ORACLE" "${oracle_args[@]}" >"$resolved_records"; then
    printf 'AUDIT-RESOLUTION scope=%s outcome=COULD-NOT-EVALUATE layer=lean-environment\n' "$scope"
    return 2
  fi
  while IFS=$'\t' read -r source package reference kind resolution; do
    [[ -n $source ]] || continue
    if [[ $resolution == true ]]; then
      printf 'AUDIT-REFERENCE scope=%s source_path=%s target_package=%s reference=%s resolved=true outcome=ESTABLISHED\n' \
        "$scope" "$source" "$package" "$reference"
      ((resolved += 1))
    elif [[ $resolution == false ]]; then
      printf 'AUDIT-REFERENCE scope=%s source_path=%s target_package=%s reference=%s resolved=false outcome=REFUTED\n' \
        "$scope" "$source" "$package" "$reference"
      ((unresolved += 1))
    else
      printf 'AUDIT-REFERENCE scope=%s source_path=%s target_package=%s reference=%s resolved=false outcome=COULD-NOT-EVALUATE layer=lean-environment\n' \
        "$scope" "$source" "$package" "$reference"
      return 2
    fi
  done <"$resolved_records"
  printf '%s\t%s\n' "$resolved" "$unresolved"
}

run_scope() {
  local scope="$1" records="$2" output="$3" mode="${4:-elaborator}"
  if ! emit_records "$scope" "$records" "$mode" >"$output"; then
    return 2
  fi
  read -r scope_resolved scope_unresolved < <(tail -n 1 "$output")
  (( scope_unresolved == 0 && scope_resolved > 0 ))
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mapfile -d '' tracked_sources < <(
  find "$AUDIT_SOURCE_ROOT/KeriBlaster" -type f -name '*.lean' -print0
  printf '%s\0' "$AUDIT_SOURCE_ROOT/KeriBlaster.lean"
)
(( ${#tracked_sources[@]} > 0 )) || {
  echo 'AUDIT-VERDICT FAIL'
  echo 'compatibility-audit: tracked source set is empty' >&2
  exit 1
}

printf 'AUDIT-IDENTITY commit=%s outcome=ESTABLISHED\n' "$AUDIT_COMMIT"
printf 'AUDIT-PIN leanBlaster=%s outcome=ESTABLISHED\n' "$AUDIT_LEAN_BLASTER_REV"
printf 'AUDIT-PIN plutusCoreBlaster=%s outcome=ESTABLISHED\n' "$AUDIT_PLUTUS_CORE_REV"
printf 'AUDIT-PIN cardanoLedgerApiBlaster=%s outcome=ESTABLISHED\n' "$AUDIT_LEDGER_API_REV"

# The package build is Lean's authoritative resolution of the complete tracked
# source graph.  The records below make its external textual reference surface
# visible and independently identify every target package and pin.
[[ -e $AUDIT_TRACKED_BUILD ]] || {
  echo 'AUDIT-IDENTITY commit=unknown outcome=COULD-NOT-EVALUATE layer=lean-elaboration'
  echo 'AUDIT-VERDICT FAIL'
  exit 1
}

if ! collect "${tracked_sources[@]}" >"$work/tracked.tsv" 2>"$work/tracked-discovery.err"; then
  cat "$work/tracked-discovery.err" >&2
  printf 'AUDIT-DISCOVERY scope=tracked outcome=COULD-NOT-EVALUATE layer=reference-discovery\n'
  printf 'AUDIT-VERDICT FAIL\n'
  exit 1
fi
tracked_collected="$(wc -l <"$work/tracked.tsv")"
if (( tracked_collected == 0 )); then
  printf 'AUDIT-DISCOVERY scope=tracked collected=0 outcome=COULD-NOT-EVALUATE layer=reference-discovery\n'
  printf 'AUDIT-VERDICT FAIL\n'
  exit 1
fi
printf 'AUDIT-DISCOVERY scope=tracked collected=%s instrument=collect-lean-references.pl/v2 window=commit:%s:scope:tracked outcome=ESTABLISHED\n' \
  "$tracked_collected" "$AUDIT_COMMIT"
tracked_rc=0
run_scope tracked "$work/tracked.tsv" "$work/tracked.out" || tracked_rc=$?
if (( tracked_rc == 2 )); then
  cat "$work/tracked.out"
  printf 'AUDIT-VERDICT FAIL\n'
  exit 1
fi
tracked_resolved="$scope_resolved"
tracked_unresolved="$scope_unresolved"
sed '$d' "$work/tracked.out"
printf 'AUDIT-RESOLVED count=%s\n' "$tracked_resolved"
printf 'AUDIT-MEASUREMENT metric=reference-resolution resolved=%s unresolved=%s denominator=%s instrument=Lean.Environment window=commit:%s:scope:tracked outcome=ESTABLISHED\n' \
  "$tracked_resolved" "$tracked_unresolved" "$((tracked_resolved + tracked_unresolved))" "$AUDIT_COMMIT"
if (( tracked_rc == 0 )); then
  printf 'AUDIT-RUN scope=tracked verdict=PASS unresolved=0\n'
else
  printf 'AUDIT-RUN scope=tracked verdict=FAIL unresolved=%s\n' "$tracked_unresolved"
fi

positive_control=true
positive_resolved=0
for probe in evaluateBuiltinFunction defaultFunSemanticsVariantC; do
  if grep -Eq $'\tplutusCoreBlaster\t[^\t]*'"$probe"$'\t' "$work/tracked.tsv" \
    && grep -Eq "reference=[^ ]*$probe resolved=true outcome=ESTABLISHED$" "$work/tracked.out"; then
    ((positive_resolved += 1))
  else
    positive_control=false
  fi
done

if [[ $positive_control == true ]]; then
  printf '%s\n' 'AUDIT-CONTROL id=tracked-required-probes kind=positive-resolution expected=resolve:required-probes observed=resolved:required-probes probes=evaluateBuiltinFunction,defaultFunSemanticsVariantC outcome=ESTABLISHED'
  positive_control=true
else
  printf 'AUDIT-CONTROL id=tracked-required-probes kind=positive-resolution expected=resolve:2 observed=resolved:%s probes=evaluateBuiltinFunction,defaultFunSemanticsVariantC outcome=REFUTED\n' \
    "$positive_resolved"
fi

collect "$AUDIT_SEED" >"$work/seed.tsv"
seed_rc=0
run_scope seeded-retired "$work/seed.tsv" "$work/seed.out" || seed_rc=$?
seed_resolved="$scope_resolved"
seed_unresolved="$scope_unresolved"
sed '$d' "$work/seed.out"
combined_unresolved=$((tracked_unresolved + seed_unresolved))
if (( combined_unresolved > 0 )); then
  printf 'AUDIT-RUN scope=tracked+seeded-retired verdict=FAIL unresolved=%s\n' "$combined_unresolved"
  printf 'AUDIT-MEASUREMENT metric=reference-resolution scope=seeded-retired resolved=%s unresolved=%s denominator=%s instrument=Lean.Environment window=commit:%s:seed:retired-reference outcome=ESTABLISHED\n' \
    "$seed_resolved" "$seed_unresolved" "$((seed_resolved + seed_unresolved))" "$AUDIT_COMMIT"
  printf '%s\n' 'AUDIT-CONTROL id=retired-cek-selector kind=seeded-retired-reference expected=unresolved observed=unresolved outcome=REFUTED'
  retired_control=true
else
  printf 'AUDIT-RUN scope=tracked+seeded-retired verdict=PASS unresolved=0\n'
  printf '%s\n' 'AUDIT-CONTROL id=retired-cek-selector kind=seeded-retired-reference expected=unresolved observed=resolved outcome=ESTABLISHED'
  retired_control=false
fi

selftests_pass=true
for leg in unresolved-in-tracked-scope namespace-move nested-namespace; do
  case "$leg" in
    unresolved-in-tracked-scope)
      selftest_source="$AUDIT_SEED"
      expected_resolved=1
      expected_unresolved=1
      ;;
    namespace-move)
      selftest_source="$AUDIT_NAMESPACE_SEED"
      expected_resolved=3
      expected_unresolved=2
      ;;
    nested-namespace)
      selftest_source="$AUDIT_NESTED_NAMESPACE_SEED"
      expected_resolved=2
      expected_unresolved=1
      ;;
  esac
  collect "$selftest_source" >"$work/selftest-$leg.tsv"
  selftest_rc=0
  run_scope "selftest-$leg" "$work/selftest-$leg.tsv" \
    "$work/selftest-$leg.out" || selftest_rc=$?
  nested_directions=true
  if [[ $leg == nested-namespace ]]; then
    sed '$d' "$work/selftest-$leg.out"
    grep -Eq 'reference=PlutusCore\.ByteStringInternal\.appendByteString resolved=false outcome=REFUTED$' \
      "$work/selftest-$leg.out" || nested_directions=false
    grep -Eq 'reference=PlutusCore\.ByteString\.PlutusCore\.ByteStringInternal\.appendByteString resolved=true outcome=ESTABLISHED$' \
      "$work/selftest-$leg.out" || nested_directions=false
  fi
  if (( selftest_rc > 0 \
      && scope_resolved == expected_resolved \
      && scope_unresolved == expected_unresolved )) \
      && [[ $nested_directions == true ]]; then
    printf 'AUDIT-SELFTEST leg=%s rc=%s outcome=REFUTED\n' "$leg" "$selftest_rc"
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=%s value=%s instrument=compatibility-audit/run_scope window=commit:%s:seed:%s outcome=ESTABLISHED\n' \
      "$leg" "$selftest_rc" "$AUDIT_COMMIT" "$leg"
  else
    printf 'AUDIT-SELFTEST leg=%s rc=%s outcome=COULD-NOT-EVALUATE layer=selftest-shape\n' \
      "$leg" "$selftest_rc"
    selftests_pass=false
  fi
done

# Exported names are accepted by Lean's elaborator even when they do not have
# their own declaration entry.  Re-running the tracked inventory through the
# old declaration-membership approximation must therefore reject a known
# exported alias while the authoritative tracked run accepts it.
export_alias_rc=0
run_scope export-alias "$work/tracked.tsv" "$work/export-alias.out" \
  declaration-membership || export_alias_rc=$?
export_alias_pass=false
if (( export_alias_rc > 0 )) \
    && grep -Eq 'reference=PlutusCore\.Default\.BuiltinSemanticsVariant resolved=false outcome=REFUTED$' \
      "$work/export-alias.out" \
    && grep -Eq 'reference=PlutusCore\.Default\.BuiltinSemanticsVariant resolved=true outcome=ESTABLISHED$' \
      "$work/tracked.out"; then
  printf 'AUDIT-SELFTEST leg=export-alias rc=%s outcome=REFUTED\n' \
    "$export_alias_rc"
  printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=export-alias value=%s instrument=compatibility-audit/declaration-membership window=commit:%s:seed:export-alias outcome=ESTABLISHED\n' \
    "$export_alias_rc" "$AUDIT_COMMIT"
  export_alias_pass=true
else
  printf 'AUDIT-SELFTEST leg=export-alias rc=%s outcome=COULD-NOT-EVALUATE layer=selftest-shape\n' \
    "$export_alias_rc"
  selftests_pass=false
fi

collector_narrowing_rc=0
if collect "$AUDIT_UNRECOGNISED_SEED" >"$work/collector-narrowing.tsv" \
    2>"$work/collector-narrowing.err"; then
  collector_narrowing_rc=0
else
  collector_narrowing_rc=$?
fi
if (( collector_narrowing_rc > 0 )) \
    && grep -Fq 'outcome=COULD-NOT-EVALUATE layer=reference-discovery' \
      "$work/collector-narrowing.err"; then
  printf 'AUDIT-SELFTEST leg=collector-narrowing rc=%s outcome=REFUTED\n' \
    "$collector_narrowing_rc"
  printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=collector-narrowing value=%s instrument=collect-lean-references.pl/v2 window=commit:%s:seed:collector-narrowing outcome=ESTABLISHED\n' \
    "$collector_narrowing_rc" "$AUDIT_COMMIT"
else
  printf 'AUDIT-SELFTEST leg=collector-narrowing rc=%s outcome=COULD-NOT-EVALUATE layer=selftest-shape\n' \
    "$collector_narrowing_rc"
  selftests_pass=false
fi

if (( tracked_unresolved == 0 && tracked_resolved > 0 )) \
    && [[ $export_alias_pass == true ]] \
    && grep -Eq 'reference=PlutusCore\.ByteStringInternal\.appendByteString resolved=false outcome=REFUTED$' \
    "$work/selftest-nested-namespace.out" \
    && grep -Eq 'reference=PlutusCore\.ByteString\.PlutusCore\.ByteStringInternal\.appendByteString resolved=true outcome=ESTABLISHED$' \
      "$work/selftest-nested-namespace.out"; then
  printf '%s\n' 'AUDIT-ORACLE agreement=elaborator both_directions=true outcome=ESTABLISHED'
else
  printf '%s\n' 'AUDIT-ORACLE agreement=elaborator both_directions=false outcome=COULD-NOT-EVALUATE layer=oracle-agreement'
  selftests_pass=false
fi

default_basic="$AUDIT_PLUTUS_CORE_ROOT/PlutusCore/Default/Basic.lean"
if [[ ! -f $default_basic ]]; then
  printf '%s\n' 'AUDIT-VARIANT variant=defaultFunSemanticsVariantE expressible=false selection=unavailable outcome=COULD-NOT-EVALUATE layer=variant-source'
  variant_evaluated=false
else
  if grep -Eq '^[[:space:]]*\|[[:space:]]*defaultFunSemanticsVariantE\b' "$default_basic"; then
    expressible=true
  else
    expressible=false
  fi
  selected="$(sed -nE 's/^[[:space:]]*\|[[:space:]]*\.plutusV3,[[:space:]]*\.postConway[[:space:]]*=>[[:space:]]*\.([A-Za-z0-9_]+).*/\1/p' "$default_basic" | head -n 1)"
  if [[ -n $selected ]] \
    && grep -q 'def PlutusVersion.toSemanticsVariant' "$default_basic" \
    && grep -q '| postConway' "$default_basic"; then
    if [[ $expressible == true && $selected == defaultFunSemanticsVariantE ]]; then
      variant_outcome=ESTABLISHED
    else
      variant_outcome=REFUTED
    fi
    printf 'AUDIT-VARIANT variant=defaultFunSemanticsVariantE expressible=%s selection=era-based:PlutusVersion.toSemanticsVariant:postConway:selected=%s outcome=%s\n' \
      "$expressible" "$selected" "$variant_outcome"
    variant_evaluated=true
  else
    printf '%s\n' 'AUDIT-VARIANT variant=defaultFunSemanticsVariantE expressible=false selection=unavailable outcome=COULD-NOT-EVALUATE layer=era-selection'
    variant_evaluated=false
  fi
fi

if (( tracked_unresolved == 0 && tracked_resolved > 0 )) \
  && [[ $positive_control == true && $retired_control == true \
     && $selftests_pass == true && $variant_evaluated == true ]]; then
  echo 'AUDIT-VERDICT PASS'
else
  echo 'AUDIT-VERDICT FAIL'
  exit 1
fi
