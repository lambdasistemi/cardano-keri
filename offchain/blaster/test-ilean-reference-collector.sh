#!/usr/bin/env bash
set -euo pipefail

collector="${1:-}"
elaborator="${2:-}"
build_root="${3:-}"
source_root="${4:-}"
artifact_root="${5:-}"

fail() {
  printf 'test-ilean-reference-collector: %s\n' "$*" >&2
  exit 1
}

[[ -n $build_root && -d $build_root ]] || fail "tracked build root is unavailable: $build_root"
[[ -n $source_root && -d $source_root ]] || fail "tracked source root is unavailable: $source_root"
[[ -n $artifact_root && -d $artifact_root ]] || fail "S2 artifact root is unavailable: $artifact_root"
[[ -x $collector ]] || fail "semantic reference collector is unavailable: $collector"
[[ -x $elaborator ]] || fail "source re-elaborator is unavailable: $elaborator"

mapfile -d '' tracked_sources < <(
  find "$source_root/KeriBlaster" -type f -name '*.lean' -print0
  printf '%s\0' "$source_root/KeriBlaster.lean"
)
(( ${#tracked_sources[@]} > 0 )) || fail 'tracked source set is empty'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Derive the denominator from the tracked source through a fresh Lean frontend
# run.  The supplied root provides the pinned dependency environment, but
# every tracked-module `.ilean` is rebuilt from source and internal imports
# prefer those fresh outputs.
source_build="$work/source-reelaboration"
"$elaborator" "$build_root" "$source_root" "$artifact_root" \
  "$source_build" "${tracked_sources[@]}"
"$collector" "$source_build" "$source_root" "${tracked_sources[@]}" \
  >"$work/source-derived.tsv"
raw="$(cut -f1-4 "$work/source-derived.tsv" | sort -u)"
total="$(grep -c . <<<"$raw" || true)"
(( total > 0 )) || fail 'Lean .ilean population is unexpectedly empty'

"$collector" "$build_root" "$source_root" "${tracked_sources[@]}" >"$work/collected.tsv"

validate_population() {
  local population="$1" observed
  observed="$(grep -c . "$population" || true)"
  [[ $observed -eq $total ]] || return 1
  diff -u <(cut -f1-4 "$population" | sort -u) <(printf '%s\n' "$raw") >/dev/null \
    || return 1
  grep -Fq $'PlutusCore.UPLC.CekMachine.State.Halt\tname\telaborated' "$population" \
    || return 1
  grep -Fq $'PlutusCore.UPLC.Term.Program.Program\tname\telaborated' "$population" \
    || return 1
  grep -Fq $'CardanoLedgerApi.V1.Credential.Credential.PubKeyCredential\tname\telaborated' "$population"
}

validate_population "$work/collected.tsv" \
  || fail 'INV-A1.v1: collector output differs from Lean .ilean population'

# The property itself can fail: deleting one compiler-reported constructor
# row must not redefine the denominator down to the smaller output.
grep -v $'PlutusCore.UPLC.CekMachine.State.Halt\tname\telaborated' \
  "$work/collected.tsv" >"$work/dropped.tsv"
if validate_population "$work/dropped.tsv"; then
  fail 'INV-A1.v1 assertion accepted a dropped elaborated constructor row'
fi
printf '%s\n' \
  'RED-PROOF invariant=INV-A1.v1 mutation=dropped-elaborated-constructor outcome=REFUTED'

mutant_build="$work/mutant-build"
mkdir -p "$mutant_build"
for source in "${tracked_sources[@]}"; do
  relative="${source#"$source_root"/}"
  module="${relative%.lean}"
  module="${module//\//.}"
  ilean_relative="${module//./\/}.ilean"
  mkdir -p "$mutant_build/$(dirname "$ilean_relative")"
  cp "$build_root/$ilean_relative" "$mutant_build/$ilean_relative"
done

# A complete, well-labelled map set with a smaller population must disagree
# with the source-derived denominator even though the collector accepts it.
target="$mutant_build/KeriBlaster/S2Fixtures.ilean"
before="$(jq '.references | length' "$target")"
jq '
  ([.references | to_entries[]
    | select(((.key | fromjson).c?) != null)
    | select(((.value.usages // []) | length) > 0)
    | select(((.key | fromjson).c.n) | test("defaultFunSemanticsVariantC|evaluateBuiltinFunction|CekMachine.State.Halt|Term.Program.Program|Credential.Credential.PubKeyCredential") | not)
    | .key][0]) as $victim
  | .references |= with_entries(select(.key != $victim))
' "$target" >"$work/shrunk.ilean"
mv "$work/shrunk.ilean" "$target"
after="$(jq '.references | length' "$target")"
(( before - after == 1 )) || fail 'shrunk-root mutation did not remove exactly one reference'
shrunk_rc=0
"$collector" "$mutant_build" "$source_root" "${tracked_sources[@]}" \
  >"$work/shrunk.tsv" 2>"$work/shrunk.err" || shrunk_rc=$?
(( shrunk_rc == 0 )) || fail 'well-formed shrunk root did not reach the population comparison'
if validate_population "$work/shrunk.tsv"; then
  fail 'source-derived denominator accepted a well-formed shrunk build root'
fi
printf '%s\n' \
  'RED-PROOF invariant=INV-246-BUILD-ROOT-PROVENANCE mutation=well-formed-shrunk-build-root outcome=REFUTED'
cp "$build_root/KeriBlaster/S2Fixtures.ilean" "$target"

# Missing and duplicate source-to-ilean mappings are both RED.
rm "$mutant_build/KeriBlaster/S2Cek.ilean"
missing_rc=0
"$collector" "$mutant_build" "$source_root" "${tracked_sources[@]}" \
  >"$work/missing.out" 2>"$work/missing.err" || missing_rc=$?
(( missing_rc > 0 )) || fail 'collector accepted a missing tracked .ilean'
printf '%s\n' \
  'RED-PROOF invariant=INV-246-TRACKED-SOURCE-ILEAN-BIJECTION mutation=missing-ilean outcome=REFUTED'

duplicate_rc=0
"$collector" "$build_root" "$source_root" "${tracked_sources[@]}" "${tracked_sources[0]}" \
  >"$work/duplicate.out" 2>"$work/duplicate.err" || duplicate_rc=$?
(( duplicate_rc > 0 )) || fail 'collector accepted a duplicate tracked source mapping'
printf '%s\n' \
  'RED-PROOF invariant=INV-246-TRACKED-SOURCE-ILEAN-BIJECTION mutation=duplicate-ilean-mapping outcome=REFUTED'

# A map whose embedded module identity does not match the tracked source is a
# foreign mapping, even when it happens to occupy the expected filesystem path.
cp "$build_root/KeriBlaster/S2Cek.ilean" "$mutant_build/KeriBlaster/S2Cek.ilean"
jq '.module = "Foreign.S2Cek"' \
  "$mutant_build/KeriBlaster/S2Cek.ilean" >"$work/foreign-map.ilean"
mv "$work/foreign-map.ilean" "$mutant_build/KeriBlaster/S2Cek.ilean"
foreign_map_rc=0
"$collector" "$mutant_build" "$source_root" "${tracked_sources[@]}" \
  >"$work/foreign-map.out" 2>"$work/foreign-map.err" || foreign_map_rc=$?
(( foreign_map_rc > 0 )) || fail 'collector accepted a foreign tracked .ilean mapping'
grep -Fq 'construct=foreign-ilean outcome=COULD-NOT-EVALUATE layer=source-mapping' \
  "$work/foreign-map.err" \
  || fail 'foreign .ilean mapping did not name its failed layer'
printf '%s\n' \
  'RED-PROOF invariant=INV-246-TRACKED-SOURCE-ILEAN-BIJECTION mutation=foreign-ilean-mapping outcome=REFUTED'

# A compiler-reported PlutusCore name attributed to no declared upstream
# module cannot be silently skipped or assigned from its source spelling.
cp "$build_root/KeriBlaster/S2Cek.ilean" "$mutant_build/KeriBlaster/S2Cek.ilean"
jq '
  .references |= with_entries(
    (.key | fromjson) as $decoded |
    if $decoded.c.n? == "PlutusCore.UPLC.CekMachine.State.Halt" then
      .key = ({c: {m: "Undeclared.Foreign.Module", n: $decoded.c.n}} | tojson)
    else . end)
' "$mutant_build/KeriBlaster/S2Cek.ilean" >"$work/foreign.ilean"
mv "$work/foreign.ilean" "$mutant_build/KeriBlaster/S2Cek.ilean"
foreign_rc=0
"$collector" "$mutant_build" "$source_root" "${tracked_sources[@]}" \
  >"$work/foreign.out" 2>"$work/foreign.err" || foreign_rc=$?
(( foreign_rc > 0 )) || fail 'collector accepted compiler-reported foreign module ownership'
grep -Fq 'outcome=COULD-NOT-EVALUATE layer=module-ownership' "$work/foreign.err" \
  || fail 'foreign module ownership did not name its failed layer'
printf '%s\n' \
  'RED-PROOF invariant=INV-246-ILEAN-MODULE-OWNERSHIP mutation=foreign-module-attribution outcome=REFUTED'

printf 'PASS: ilean collector matched collected=%s total=%s classes=direct-imports,elaborated-constants\n' \
  "$total" "$total"
