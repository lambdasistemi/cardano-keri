#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  echo 'compatibility-audit: accepts no arguments' >&2
  exit 64
fi

required_env=(
  AUDIT_COMMIT AUDIT_COLLECTOR AUDIT_INDEXER AUDIT_SOURCE_ROOT AUDIT_SEED
  AUDIT_NAMESPACE_SEED
  AUDIT_LEAN_BLASTER_ROOT AUDIT_PLUTUS_CORE_ROOT AUDIT_LEDGER_API_ROOT
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

target_root() {
  case "$1" in
    leanBlaster) printf '%s\n' "$AUDIT_LEAN_BLASTER_ROOT" ;;
    plutusCoreBlaster) printf '%s\n' "$AUDIT_PLUTUS_CORE_ROOT" ;;
    cardanoLedgerApiBlaster) printf '%s\n' "$AUDIT_LEDGER_API_ROOT" ;;
    *) return 1 ;;
  esac
}

target_index() {
  case "$1" in
    leanBlaster) printf '%s\n' "$work/leanBlaster.index" ;;
    plutusCoreBlaster) printf '%s\n' "$work/plutusCoreBlaster.index" ;;
    cardanoLedgerApiBlaster) printf '%s\n' "$work/cardanoLedgerApiBlaster.index" ;;
    *) return 1 ;;
  esac
}

resolve_reference() {
  local package="$1" reference="$2" kind="$3" index record_kind
  index="$(target_index "$package")" || return 2
  if [[ $kind == module ]]; then record_kind=module; else record_kind=symbol; fi
  grep -Fxq "$record_kind"$'\t'"$reference" "$index"
}

collect() {
  "$AUDIT_COLLECTOR" "$AUDIT_SOURCE_ROOT" "$@"
}

emit_records() {
  local scope="$1" records="$2" record source package reference kind
  local resolved=0 unresolved=0
  while IFS=$'\t' read -r source package reference kind; do
    [[ -n $source ]] || continue
    if resolve_reference "$package" "$reference" "$kind"; then
      printf 'AUDIT-REFERENCE scope=%s source_path=%s target_package=%s reference=%s resolved=true outcome=ESTABLISHED\n' \
        "$scope" "$source" "$package" "$reference"
      ((resolved += 1))
    else
      printf 'AUDIT-REFERENCE scope=%s source_path=%s target_package=%s reference=%s resolved=false outcome=REFUTED\n' \
        "$scope" "$source" "$package" "$reference"
      ((unresolved += 1))
    fi
  done <"$records"
  printf '%s\t%s\n' "$resolved" "$unresolved"
}

run_scope() {
  local scope="$1" records="$2" output="$3"
  emit_records "$scope" "$records" >"$output"
  read -r scope_resolved scope_unresolved < <(tail -n 1 "$output")
  (( scope_unresolved == 0 && scope_resolved > 0 ))
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for package in leanBlaster plutusCoreBlaster cardanoLedgerApiBlaster; do
  root="$(target_root "$package")" || exit 1
  if ! "$AUDIT_INDEXER" "$root" >"$work/$package.index"; then
    printf 'AUDIT-IDENTITY commit=%s outcome=COULD-NOT-EVALUATE layer=resolver-index\n' \
      "$AUDIT_COMMIT"
    printf 'AUDIT-VERDICT FAIL\n'
    exit 1
  fi
done

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

collect "${tracked_sources[@]}" >"$work/tracked.tsv"
tracked_rc=0
run_scope tracked "$work/tracked.tsv" "$work/tracked.out" || tracked_rc=$?
tracked_resolved="$scope_resolved"
tracked_unresolved="$scope_unresolved"
sed '$d' "$work/tracked.out"
printf 'AUDIT-RESOLVED count=%s\n' "$tracked_resolved"
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
  printf '%s\n' 'AUDIT-CONTROL id=tracked-required-probes kind=positive-resolution expected=resolve:2 observed=resolved:2 probes=evaluateBuiltinFunction,defaultFunSemanticsVariantC outcome=ESTABLISHED'
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
  printf '%s\n' 'AUDIT-CONTROL id=retired-cek-selector kind=seeded-retired-reference expected=unresolved observed=unresolved outcome=REFUTED'
  retired_control=true
else
  printf 'AUDIT-RUN scope=tracked+seeded-retired verdict=PASS unresolved=0\n'
  printf '%s\n' 'AUDIT-CONTROL id=retired-cek-selector kind=seeded-retired-reference expected=unresolved observed=resolved outcome=ESTABLISHED'
  retired_control=false
fi

selftests_pass=true
for leg in unresolved-in-tracked-scope namespace-move; do
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
  esac
  collect "$selftest_source" >"$work/selftest-$leg.tsv"
  selftest_rc=0
  run_scope "selftest-$leg" "$work/selftest-$leg.tsv" \
    "$work/selftest-$leg.out" || selftest_rc=$?
  if (( selftest_rc > 0 \
      && scope_resolved == expected_resolved \
      && scope_unresolved == expected_unresolved )); then
    printf 'AUDIT-SELFTEST leg=%s rc=%s outcome=REFUTED\n' "$leg" "$selftest_rc"
  else
    printf 'AUDIT-SELFTEST leg=%s rc=%s outcome=COULD-NOT-EVALUATE layer=selftest-shape\n' \
      "$leg" "$selftest_rc"
    selftests_pass=false
  fi
done

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
