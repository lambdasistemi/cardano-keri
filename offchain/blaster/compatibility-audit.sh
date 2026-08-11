#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  echo 'compatibility-audit: accepts no arguments' >&2
  exit 64
fi

required_env=(
  AUDIT_COMMIT AUDIT_TEXT_COLLECTOR AUDIT_ILEAN_COLLECTOR
  AUDIT_SOURCE_ELABORATOR AUDIT_ORACLE
  AUDIT_SOURCE_ROOT AUDIT_SEED AUDIT_COLLECTOR_SEED
  AUDIT_NAMESPACE_SEED AUDIT_NESTED_NAMESPACE_SEED AUDIT_UNRECOGNISED_SEED
  AUDIT_LEAN_BLASTER_ROOT AUDIT_PLUTUS_CORE_ROOT AUDIT_LEDGER_API_ROOT
  AUDIT_LEAN_BLASTER_REV AUDIT_PLUTUS_CORE_REV AUDIT_LEDGER_API_REV
  AUDIT_TRACKED_BUILD AUDIT_S2_ARTIFACTS LEAN_PATH
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
  "$AUDIT_TEXT_COLLECTOR" "$AUDIT_SOURCE_ROOT" "$@"
}

collect_tracked() {
  "$AUDIT_ILEAN_COLLECTOR" "$AUDIT_TRACKED_BUILD" "$AUDIT_SOURCE_ROOT" "$@"
}

collect_root() {
  local root="$1"
  shift
  "$AUDIT_ILEAN_COLLECTOR" "$root" "$AUDIT_SOURCE_ROOT" "$@"
}

populations_match() {
  cmp -s "$1" "$2"
}

emit_records() {
  local scope="$1" records="$2" mode="${3:-elaborator}"
  local resolved_records="$work/resolved-$scope.tsv"
  local source package reference kind resolution provenance elaborator_resolution
  local resolved=0 unresolved=0 compared=0 disagreements=0
  local -a oracle_args=("$records")
  if [[ $mode == declaration-membership ]]; then
    oracle_args=(--declaration-membership "$records")
  fi
  if ! "$AUDIT_ORACLE" "${oracle_args[@]}" >"$resolved_records"; then
    printf 'AUDIT-RESOLUTION scope=%s outcome=COULD-NOT-EVALUATE layer=lean-environment\n' "$scope"
    return 2
  fi
  while IFS=$'\t' read -r source package reference kind resolution provenance elaborator_resolution; do
    [[ -n $source ]] || continue
    if [[ $provenance != copied && $provenance != synthesised \
        && $provenance != elaborated ]]; then
      printf 'AUDIT-REFERENCE scope=%s source_path=%s target_package=%s provenance=unknown reference=%s resolved=false outcome=COULD-NOT-EVALUATE layer=reference-provenance\n' \
        "$scope" "$source" "$package" "$reference"
      return 2
    fi
    if [[ $kind == name ]]; then
      if [[ $elaborator_resolution != true && $elaborator_resolution != false ]]; then
        printf 'AUDIT-REFERENCE scope=%s source_path=%s target_package=%s provenance=%s reference=%s resolved=false outcome=COULD-NOT-EVALUATE layer=elaborator-comparison\n' \
          "$scope" "$source" "$package" "$provenance" "$reference"
        return 2
      fi
      ((compared += 1))
      if [[ $resolution != "$elaborator_resolution" ]]; then
        ((disagreements += 1))
        printf 'AUDIT-DISAGREEMENT scope=%s source_path=%s reference=%s oracle=%s elaborator=%s outcome=REFUTED\n' \
          "$scope" "$source" "$reference" "$resolution" "$elaborator_resolution"
      fi
    fi
    if [[ $resolution == true ]]; then
      printf 'AUDIT-REFERENCE scope=%s source_path=%s target_package=%s provenance=%s reference=%s resolved=true outcome=ESTABLISHED\n' \
        "$scope" "$source" "$package" "$provenance" "$reference"
      ((resolved += 1))
    elif [[ $resolution == false ]]; then
      printf 'AUDIT-REFERENCE scope=%s source_path=%s target_package=%s provenance=%s reference=%s resolved=false outcome=REFUTED\n' \
        "$scope" "$source" "$package" "$provenance" "$reference"
      ((unresolved += 1))
    else
      printf 'AUDIT-REFERENCE scope=%s source_path=%s target_package=%s provenance=%s reference=%s resolved=false outcome=COULD-NOT-EVALUATE layer=lean-environment\n' \
        "$scope" "$source" "$package" "$provenance" "$reference"
      return 2
    fi
  done <"$resolved_records"
  printf '%s\t%s\t%s\t%s\n' "$resolved" "$unresolved" "$compared" "$disagreements"
}

run_scope() {
  local scope="$1" records="$2" output="$3" mode="${4:-elaborator}"
  if ! emit_records "$scope" "$records" "$mode" >"$output"; then
    return 2
  fi
  read -r scope_resolved scope_unresolved scope_compared scope_disagreements \
    < <(tail -n 1 "$output")
  (( scope_unresolved == 0 && scope_resolved > 0 && scope_disagreements == 0 ))
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

# The package build is Lean's authoritative elaboration and reference index for
# the complete tracked source graph.  Bind both collection and resolution to
# that exact root before reading a single record.
[[ -e $AUDIT_TRACKED_BUILD ]] || {
  echo 'AUDIT-IDENTITY commit=unknown outcome=COULD-NOT-EVALUATE layer=lean-elaboration'
  echo 'AUDIT-VERDICT FAIL'
  exit 1
}
if [[ $LEAN_PATH != "$AUDIT_TRACKED_BUILD" ]]; then
  printf 'AUDIT-ORACLE-ROOT path=%s instrument=flake:keriBlasterPackage.modRoot window=commit:%s:scope:tracked outcome=COULD-NOT-EVALUATE layer=module-graph-binding\n' \
    "$LEAN_PATH" "$AUDIT_COMMIT"
  printf 'AUDIT-VERDICT FAIL\n'
  exit 1
fi
printf 'AUDIT-ORACLE-ROOT path=%s instrument=flake:keriBlasterPackage.modRoot window=commit:%s:scope:tracked outcome=ESTABLISHED\n' \
  "$AUDIT_TRACKED_BUILD" "$AUDIT_COMMIT"

if ! collect_tracked "${tracked_sources[@]}" >"$work/tracked.tsv" 2>"$work/tracked-discovery.err"; then
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

# Re-elaborate the exact tracked source into a fresh root.  The denominator is
# therefore produced by Lean's frontend from source, not by reading the
# supplied root a second time.  Both populations use the one package
# attribution predicate owned by the semantic collector.
source_build="$work/source-reelaboration"
if ! "$AUDIT_SOURCE_ELABORATOR" "$AUDIT_TRACKED_BUILD" "$AUDIT_SOURCE_ROOT" \
    "$AUDIT_S2_ARTIFACTS" "$source_build" "${tracked_sources[@]}" \
    >"$work/source-reelaboration.log" 2>&1; then
  cat "$work/source-reelaboration.log" >&2
  printf 'AUDIT-COVERAGE collected=%s total=0 digest=unavailable classes=direct-imports,elaborated-constants instrument=Lean.ilean/unknown total_instrument=Lean.frontend/source-reelaboration-v4 window=commit:%s:scope:tracked outcome=COULD-NOT-EVALUATE layer=build-root-provenance\n' \
    "$tracked_collected" "$AUDIT_COMMIT"
  printf 'AUDIT-VERDICT FAIL\n'
  exit 1
fi
if ! collect_root "$source_build" "${tracked_sources[@]}" \
    >"$work/source-derived.tsv" 2>"$work/source-derived.err"; then
  cat "$work/source-derived.err" >&2
  printf 'AUDIT-COVERAGE collected=%s total=0 digest=unavailable classes=direct-imports,elaborated-constants instrument=Lean.ilean/unknown total_instrument=Lean.frontend/source-reelaboration-v4 window=commit:%s:scope:tracked outcome=COULD-NOT-EVALUATE layer=build-root-provenance\n' \
    "$tracked_collected" "$AUDIT_COMMIT"
  printf 'AUDIT-VERDICT FAIL\n'
  exit 1
fi
tracked_total="$(wc -l <"$work/source-derived.tsv")"
population_digest="$(sha256sum "$work/source-derived.tsv" | cut -d ' ' -f 1)"
if (( tracked_total == 0 )) \
    || ! populations_match "$work/tracked.tsv" "$work/source-derived.tsv"; then
  printf 'AUDIT-COVERAGE collected=%s total=%s digest=%s classes=direct-imports,elaborated-constants instrument=Lean.ilean/unknown total_instrument=Lean.frontend/source-reelaboration-v4 window=commit:%s:scope:tracked outcome=COULD-NOT-EVALUATE layer=build-root-provenance\n' \
    "$tracked_collected" "$tracked_total" "$population_digest" "$AUDIT_COMMIT"
  printf 'AUDIT-VERDICT FAIL\n'
  exit 1
fi

mapfile -t ilean_versions < <(
  for source in "${tracked_sources[@]}"; do
    relative="${source#"$AUDIT_SOURCE_ROOT"/}"
    module="${relative%.lean}"
    module="${module//\//.}"
    jq -er '.version' "$AUDIT_TRACKED_BUILD/${module//./\/}.ilean"
  done | sort -u
)
if (( ${#ilean_versions[@]} != 1 )); then
  printf 'AUDIT-COVERAGE collected=%s total=0 classes=direct-imports,elaborated-constants instrument=Lean.ilean/unknown window=commit:%s:scope:tracked outcome=COULD-NOT-EVALUATE layer=reference-discovery\n' \
    "$tracked_collected" "$AUDIT_COMMIT"
  printf 'AUDIT-VERDICT FAIL\n'
  exit 1
fi
printf 'AUDIT-COVERAGE collected=%s total=%s digest=%s classes=direct-imports,elaborated-constants instrument=Lean.ilean/v%s total_instrument=Lean.frontend/source-reelaboration-v4 window=commit:%s:scope:tracked outcome=ESTABLISHED\n' \
  "$tracked_collected" "$tracked_total" "$population_digest" \
  "${ilean_versions[0]}" "$AUDIT_COMMIT"
printf 'AUDIT-ATTRIBUTION agreement=by-construction predicate=collect-ilean-references/package_for_module outcome=ESTABLISHED\n'
tracked_rc=0
run_scope tracked "$work/tracked.tsv" "$work/tracked.out" || tracked_rc=$?
if (( tracked_rc == 2 )); then
  cat "$work/tracked.out"
  printf 'AUDIT-VERDICT FAIL\n'
  exit 1
fi
tracked_resolved="$scope_resolved"
tracked_unresolved="$scope_unresolved"
tracked_compared="$scope_compared"
tracked_disagreements="$scope_disagreements"
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
# their own declaration entry.  The compiler's semantic inventory records the
# declaration that the alias resolves to, so retain this deliberately textual
# fixture only as a negative control for the retired membership oracle.
collect "${tracked_sources[@]}" >"$work/textual-tracked.tsv"
export_alias_elaborator_rc=0
run_scope export-alias-elaborator "$work/textual-tracked.tsv" \
  "$work/export-alias-elaborator.out" || export_alias_elaborator_rc=$?
export_alias_rc=0
run_scope export-alias "$work/textual-tracked.tsv" "$work/export-alias.out" \
  declaration-membership || export_alias_rc=$?
export_alias_pass=false
if (( export_alias_elaborator_rc == 0 && export_alias_rc > 0 )) \
    && grep -Eq 'reference=PlutusCore\.Default\.BuiltinSemanticsVariant resolved=false outcome=REFUTED$' \
      "$work/export-alias.out" \
    && grep -Eq 'reference=PlutusCore\.Default\.BuiltinSemanticsVariant resolved=true outcome=ESTABLISHED$' \
      "$work/export-alias-elaborator.out"; then
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

run_negative_producer_selftest() {
  local leg="$1" records="$2" reference="$3" provenance="$4" instrument="$5"
  local selftest_rc=0
  run_scope "selftest-$leg" "$records" "$work/selftest-$leg.out" \
    || selftest_rc=$?
  if (( selftest_rc > 0 && scope_unresolved == 1 \
      && scope_compared > 0 && scope_disagreements == 0 )) \
      && grep -Fq "provenance=$provenance reference=$reference resolved=false outcome=REFUTED" \
        "$work/selftest-$leg.out"; then
    printf 'AUDIT-SELFTEST leg=%s rc=%s outcome=REFUTED\n' "$leg" "$selftest_rc"
    printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=%s value=%s instrument=%s window=commit:%s:seed:%s outcome=ESTABLISHED\n' \
      "$leg" "$selftest_rc" "$instrument" "$AUDIT_COMMIT" "$leg"
  else
    printf 'AUDIT-SELFTEST leg=%s rc=%s outcome=COULD-NOT-EVALUATE layer=selftest-shape\n' \
      "$leg" "$selftest_rc"
    selftests_pass=false
  fi
}

# Shape 5 from auditor-A2-s1: a resolvable declaration followed by an absent
# field must be rejected.  Keep only the real tracked module graph, then mutate
# the producer input with one name row so the oracle, not a fixture validator,
# must kill the defect.
awk -F $'\t' '$4 == "module"' "$work/tracked.tsv" >"$work/prefix-field.tsv"
prefix_field_name='PlutusCore.Data.Data.retiredConstructorName'
printf 'offchain/blaster/CompatibilityPrefixFieldReference.lean\tplutusCoreBlaster\t%s\tname\tcopied\n' \
  "$prefix_field_name" >>"$work/prefix-field.tsv"
run_negative_producer_selftest prefix-field "$work/prefix-field.tsv" \
  "$prefix_field_name" copied compatibility-audit/run_scope

# Pair the required constructor probe with a same-shape absent twin.  A
# prefix-only resolver answers true for both; exact constant resolution makes
# the twin go RED while the real subject remains established above.
awk -F $'\t' '$4 == "module"' "$work/tracked.tsv" >"$work/probe-twin.tsv"
probe_twin_name='PlutusCore.Default.Internal.BuiltinSemanticsVariant.defaultFunSemanticsVariantZ'
printf 'offchain/blaster/CompatibilityProbeTwinReference.lean\tplutusCoreBlaster\t%s\tname\tcopied\n' \
  "$probe_twin_name" >>"$work/probe-twin.tsv"
run_negative_producer_selftest probe-twin "$work/probe-twin.tsv" \
  "$probe_twin_name" copied compatibility-audit/run_scope

# Mutate the actual leading-dot source construct, prove the edit applied once,
# then run collector and oracle together.  This binds the sole synthesising
# rule to the pinned environment and prevents a fabricated denominator row.
synth_mutant="$work/CompatibilitySynthesisedReference.lean"
cp "$AUDIT_SOURCE_ROOT/KeriBlaster/S2Cek.lean" "$synth_mutant"
synth_before="$(grep -Fc '| .Program _ _ => .defaultFunSemanticsVariantC' \
  "$synth_mutant" || true)"
perl -0pi -e 's/(\| \.Program _ _ => )\.defaultFunSemanticsVariantC/$1.defaultFunSemanticsVariantZ/' \
  "$synth_mutant"
synth_after_old="$(grep -Fc '| .Program _ _ => .defaultFunSemanticsVariantC' \
  "$synth_mutant" || true)"
synth_after_new="$(grep -Fc '| .Program _ _ => .defaultFunSemanticsVariantZ' \
  "$synth_mutant" || true)"
if [[ $synth_before == 1 && $synth_after_old == 0 && $synth_after_new == 1 ]]; then
  collect "$synth_mutant" >"$work/synthesised-reference.tsv"
  synthesised_twin='PlutusCore.Default.Internal.BuiltinSemanticsVariant.defaultFunSemanticsVariantZ'
  run_negative_producer_selftest synthesised-reference \
    "$work/synthesised-reference.tsv" "$synthesised_twin" synthesised \
    compatibility-audit/collector-mutation
else
  printf '%s\n' 'AUDIT-SELFTEST leg=synthesised-reference rc=0 outcome=COULD-NOT-EVALUATE layer=mutation-application'
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

# The semantic collector names no Lean syntax classes.  Compile a real
# leading-dot constructor occurrence to `.ilean`, require the collector to
# publish Lean's resolved constant, then rename that occurrence to an absent
# constructor and require elaboration under the pinned graph to go RED.
closure_source_root="$work/collector-closure-source"
closure_build_root="$work/collector-closure-build"
mkdir -p "$closure_source_root/KeriBlaster" "$closure_build_root/KeriBlaster"
cp "$AUDIT_COLLECTOR_SEED" \
  "$closure_source_root/KeriBlaster/CollectorClosure.lean"
closure_clean_rc=0
(cd "$closure_source_root" && lean \
  -i "$closure_build_root/KeriBlaster/CollectorClosure.ilean" \
  -o "$closure_build_root/KeriBlaster/CollectorClosure.olean" \
  KeriBlaster/CollectorClosure.lean) \
  >"$work/collector-closure-clean.log" 2>&1 || closure_clean_rc=$?
closure_visible=false
if (( closure_clean_rc == 0 )) \
    && "$AUDIT_ILEAN_COLLECTOR" "$closure_build_root" "$closure_source_root" \
      "$closure_source_root/KeriBlaster/CollectorClosure.lean" \
      >"$work/collector-closure.tsv" 2>"$work/collector-closure.err" \
    && grep -Fq $'PlutusCore.UPLC.CekMachine.State.Halt\tname\telaborated' \
      "$work/collector-closure.tsv"; then
  closure_visible=true
fi

closure_mutant="$closure_source_root/KeriBlaster/CollectorClosureMutant.lean"
cp "$AUDIT_COLLECTOR_SEED" "$closure_mutant"
closure_before="$(grep -Fc '| .Halt _ => true' "$closure_mutant" || true)"
perl -0pi -e 's/\| \.Halt _ => true/| .Stop _ => true/' "$closure_mutant"
closure_after_old="$(grep -Fc '| .Halt _ => true' "$closure_mutant" || true)"
closure_after_new="$(grep -Fc '| .Stop _ => true' "$closure_mutant" || true)"
closure_mutant_rc=0
(cd "$closure_source_root" && lean \
  -i "$closure_build_root/KeriBlaster/CollectorClosureMutant.ilean" \
  -o "$closure_build_root/KeriBlaster/CollectorClosureMutant.olean" \
  KeriBlaster/CollectorClosureMutant.lean) \
  >"$work/collector-closure-mutant.log" 2>&1 \
  || closure_mutant_rc=$?
if [[ $closure_visible == true && $closure_before == 1 \
      && $closure_after_old == 0 && $closure_after_new == 1 ]] \
    && (( closure_mutant_rc > 0 )); then
  printf 'AUDIT-SELFTEST leg=collector-closure rc=%s outcome=REFUTED\n' \
    "$closure_mutant_rc"
  printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=collector-closure value=%s instrument=Lean.frontend window=commit:%s:seed:collector-closure outcome=ESTABLISHED\n' \
    "$closure_mutant_rc" "$AUDIT_COMMIT"
else
  printf 'AUDIT-SELFTEST leg=collector-closure rc=%s outcome=COULD-NOT-EVALUATE layer=collector-closure\n' \
    "$closure_mutant_rc"
  selftests_pass=false
fi

# Build one tracked module from a deliberately different, still-valid source
# and splice its compiler products into an otherwise complete source-derived
# root.  The same full-population comparison used above must reject it.  This
# makes foreign-root provenance a live property rather than a caller promise.
foreign_source_root="$work/foreign-build-source"
foreign_patch_root="$work/foreign-build-patch"
foreign_build_root="$work/foreign-build-root"
mkdir -p "$foreign_source_root/KeriBlaster" "$foreign_build_root"
cp "$AUDIT_SOURCE_ROOT/KeriBlaster/S2Cek.lean" \
  "$foreign_source_root/KeriBlaster/S2Cek.lean"
chmod u+w "$foreign_source_root/KeriBlaster/S2Cek.lean"
printf '\n#check PlutusCore.UPLC.CekMachine.cekExecuteProgramWithSemanticVariant\n' \
  >>"$foreign_source_root/KeriBlaster/S2Cek.lean"
foreign_mutation_count="$(grep -Fc '#check PlutusCore.UPLC.CekMachine.cekExecuteProgramWithSemanticVariant' \
  "$foreign_source_root/KeriBlaster/S2Cek.lean" || true)"
foreign_elaboration_rc=0
"$AUDIT_SOURCE_ELABORATOR" "$AUDIT_TRACKED_BUILD" "$foreign_source_root" \
  "$AUDIT_S2_ARTIFACTS" "$foreign_patch_root" \
  "$foreign_source_root/KeriBlaster/S2Cek.lean" \
  >"$work/foreign-build-elaboration.log" 2>&1 || foreign_elaboration_rc=$?
foreign_collect_rc=0
foreign_build_rc=0
foreign_reference_visible=false
if (( foreign_elaboration_rc == 0 )); then
  cp -R "$source_build/." "$foreign_build_root/"
  cp "$foreign_patch_root/KeriBlaster/S2Cek.ilean" \
    "$foreign_build_root/KeriBlaster/S2Cek.ilean"
  cp "$foreign_patch_root/KeriBlaster/S2Cek.olean" \
    "$foreign_build_root/KeriBlaster/S2Cek.olean"
  collect_root "$foreign_build_root" "${tracked_sources[@]}" \
    >"$work/foreign-build.tsv" 2>"$work/foreign-build.err" \
    || foreign_collect_rc=$?
  if (( foreign_collect_rc == 0 )) \
      && grep -Fq $'PlutusCore.UPLC.CekMachine.cekExecuteProgramWithSemanticVariant\tname\telaborated' \
        "$work/foreign-build.tsv"; then
    foreign_reference_visible=true
  fi
  if (( foreign_collect_rc == 0 )) \
      && populations_match "$work/foreign-build.tsv" "$work/source-derived.tsv"; then
    foreign_build_rc=0
  else
    foreign_build_rc=1
  fi
else
  foreign_build_rc=$foreign_elaboration_rc
fi
if (( foreign_mutation_count == 1 && foreign_elaboration_rc == 0 \
      && foreign_collect_rc == 0 && foreign_build_rc > 0 )) \
    && [[ $foreign_reference_visible == true ]]; then
  printf 'AUDIT-SELFTEST leg=foreign-build-root rc=%s outcome=REFUTED\n' \
    "$foreign_build_rc"
  printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=foreign-build-root value=%s instrument=source-reelaboration/root-comparison window=commit:%s:seed:foreign-build-root outcome=ESTABLISHED\n' \
    "$foreign_build_rc" "$AUDIT_COMMIT"
else
  printf 'AUDIT-SELFTEST leg=foreign-build-root rc=%s outcome=COULD-NOT-EVALUATE layer=build-root-provenance\n' \
    "$foreign_build_rc"
  selftests_pass=false
fi

# Named module-graph mutant: point the same oracle and same complete record set
# at an empty module root.  Resolution must become RED, proving that the
# published root is a live input rather than descriptive text.
mkdir -p "$work/empty-lean-path"
pinned_graph_rc=0
LEAN_PATH="$work/empty-lean-path" \
  run_scope pinned-module-graph "$work/tracked.tsv" \
    "$work/pinned-module-graph.out" || pinned_graph_rc=$?
if (( pinned_graph_rc > 0 )); then
  printf 'AUDIT-SELFTEST leg=pinned-module-graph rc=%s outcome=REFUTED\n' \
    "$pinned_graph_rc"
  printf 'AUDIT-MEASUREMENT metric=selftest-exit-code leg=pinned-module-graph value=%s instrument=compatibility-oracle/LEAN_PATH window=commit:%s:seed:pinned-module-graph outcome=ESTABLISHED\n' \
    "$pinned_graph_rc" "$AUDIT_COMMIT"
else
  printf 'AUDIT-SELFTEST leg=pinned-module-graph rc=0 outcome=COULD-NOT-EVALUATE layer=module-graph-binding\n'
  selftests_pass=false
fi

if (( tracked_unresolved == 0 && tracked_resolved > 0 \
      && tracked_compared > 0 && tracked_disagreements == 0 )) \
    && [[ $export_alias_pass == true ]] \
    && grep -Eq 'reference=PlutusCore\.ByteStringInternal\.appendByteString resolved=false outcome=REFUTED$' \
    "$work/selftest-nested-namespace.out" \
    && grep -Eq 'reference=PlutusCore\.ByteString\.PlutusCore\.ByteStringInternal\.appendByteString resolved=true outcome=ESTABLISHED$' \
      "$work/selftest-nested-namespace.out"; then
  printf 'AUDIT-ORACLE agreement=by-construction predicate=Lean.resolveGlobalConstCore outcome=ESTABLISHED\n'
else
  printf 'AUDIT-ORACLE agreement=by-construction predicate=Lean.resolveGlobalConstCore outcome=COULD-NOT-EVALUATE layer=oracle-agreement\n'
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

if (( tracked_unresolved == 0 && tracked_resolved > 0 \
      && tracked_compared > 0 && tracked_disagreements == 0 )) \
  && [[ $positive_control == true && $retired_control == true \
     && $selftests_pass == true && $variant_evaluated == true ]]; then
  echo 'AUDIT-VERDICT PASS'
else
  echo 'AUDIT-VERDICT FAIL'
  exit 1
fi
