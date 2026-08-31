#!/usr/bin/env bash
set -euo pipefail

elaborator="${1:-}"
build_root="${2:-}"
source_root="${3:-}"
artifact_root="${4:-}"

fail() {
  printf 'test-elaboration-order: %s\n' "$*" >&2
  exit 1
}

if ! command -v lean >/dev/null 2>&1; then
  printf '%s\n' \
    'AUDIT-DISCOVERY construct=elaboration-order-test outcome=COULD-NOT-EVALUATE layer=toolchain-reachability' >&2
  fail 'lean compiler is not on PATH; run the harness through the flake-owned runner'
fi

[[ -n $elaborator && -x $elaborator ]] \
  || fail "source re-elaborator is unavailable or not executable: $elaborator"
[[ -n $build_root && -d $build_root ]] \
  || fail "tracked build root is unavailable: $build_root"
[[ -n $source_root && -d $source_root ]] \
  || fail "tracked source root is unavailable: $source_root"
[[ -n $artifact_root && -d $artifact_root ]] \
  || fail "artifact root is unavailable: $artifact_root"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

position_of() {
  local order="$1" target="$2"
  awk -F, -v target="$target" '
    {
      for (i = 1; i <= NF; i++) {
        if ($i == target) {
          print i
          found = 1
          exit
        }
      }
    }
    END { if (!found) exit 1 }
  ' <<<"$order"
}

count_violations() {
  local fixture_root="$1" order="$2"
  local violations=0 source relative module dependency module_position dependency_position

  while IFS= read -r -d '' source; do
    relative="${source#"$fixture_root"/}"
    [[ $relative != KeriBlaster.lean ]] || continue
    module="${relative%.lean}"
    module="${module//\//.}"

    while IFS= read -r dependency; do
      [[ -n $dependency ]] || continue
      module_position="$(position_of "$order" "$module")" \
        || fail "module $module is absent from order $order"
      dependency_position="$(position_of "$order" "$dependency")" \
        || fail "dependency $dependency is absent from order $order"
      if (( dependency_position >= module_position )); then
        violations=$((violations + 1))
      fi
    done < <(
      sed -nE \
        's/^[[:space:]]*import[[:space:]]+(KeriBlaster\.[A-Za-z0-9_.]+).*/\1/p' \
        "$source"
    )
  done < <(find "$fixture_root" -type f -name '*.lean' -print0)

  printf '%d\n' "$violations"
}

extract_order() {
  local stderr_file="$1" expected_count="$2"
  local -a lines=()
  local declared_count order observed_count

  mapfile -t lines < <(
    grep -E '^ELABORATION-ORDER count=[0-9]+ derived=[^[:space:]]+$' \
      "$stderr_file" || true
  )
  (( ${#lines[@]} == 1 )) \
    || fail "expected one ELABORATION-ORDER line in $stderr_file, observed ${#lines[@]}"
  declared_count="$(sed -nE 's/^ELABORATION-ORDER count=([0-9]+) .*/\1/p' <<<"${lines[0]}")"
  order="$(sed -nE 's/^ELABORATION-ORDER count=[0-9]+ derived=([^[:space:]]+)$/\1/p' <<<"${lines[0]}")"
  observed_count="$(awk -F, '{ print NF }' <<<"$order")"
  [[ $declared_count == "$expected_count" && $observed_count == "$expected_count" ]] \
    || fail "order count mismatch: declared=$declared_count observed=$observed_count expected=$expected_count"
  printf '%s\n' "$order"
}

assert_compiled() {
  local output_root="$1"
  shift
  local module relative
  for module in "$@"; do
    relative="${module//./\/}"
    [[ -f "$output_root/$relative.ilean" && -f "$output_root/$relative.olean" ]] \
      || fail "compiled artifacts are absent for $module"
  done
}

# Positive control: prove this environment can elaborate a fixture whose
# lexical order already respects its declared dependency.
mkdir -p "$work/c0/KeriBlaster" "$work/c0-output"
cat <<'LEAN' >"$work/c0/KeriBlaster/Alpha.lean"
def alphaValue : Nat := 1
LEAN
cat <<'LEAN' >"$work/c0/KeriBlaster/Omega.lean"
import KeriBlaster.Alpha
def omegaValue : Nat := 2
LEAN
cat <<'LEAN' >"$work/c0/KeriBlaster.lean"
import KeriBlaster.Alpha
import KeriBlaster.Omega
LEAN
if ! timeout 120 "$elaborator" \
    "$build_root" "$work/c0" "$artifact_root" "$work/c0-output" \
    "$work/c0/KeriBlaster/Alpha.lean" \
    "$work/c0/KeriBlaster/Omega.lean" \
    "$work/c0/KeriBlaster.lean" \
    >"$work/c0.stdout" 2>"$work/c0.stderr"; then
  cat "$work/c0.stderr" >&2
  fail 'positive control could not elaborate a lexically valid fixture'
fi
assert_compiled "$work/c0-output" \
  KeriBlaster.Alpha KeriBlaster.Omega KeriBlaster

# C1: manufacture a transitive lexical-order defect rather than relying on
# today's tracked module names. The three-module chain distinguishes a real
# topological order from local heuristics such as import count or filename.
mkdir -p "$work/c1/KeriBlaster" "$work/c1-output"
cat <<'LEAN' >"$work/c1/KeriBlaster/Alpha.lean"
import KeriBlaster.Beta
def alphaValue : Nat := 1
LEAN
cat <<'LEAN' >"$work/c1/KeriBlaster/Beta.lean"
import KeriBlaster.Gamma
def betaValue : Nat := 2
LEAN
cat <<'LEAN' >"$work/c1/KeriBlaster/Gamma.lean"
def gammaValue : Nat := 3
LEAN
cat <<'LEAN' >"$work/c1/KeriBlaster.lean"
import KeriBlaster.Alpha
import KeriBlaster.Beta
import KeriBlaster.Gamma
LEAN
c1_chain=(KeriBlaster.Gamma KeriBlaster.Beta KeriBlaster.Alpha)
chain_depth=${#c1_chain[@]}
(( chain_depth >= 3 )) \
  || fail "C1 fixture chain depth $chain_depth is below required floor 3"
for (( chain_index = 1; chain_index < chain_depth; chain_index++ )); do
  prerequisite="${c1_chain[$((chain_index - 1))]}"
  importer="${c1_chain[$chain_index]}"
  importer_file="${importer#KeriBlaster.}"
  grep -Fxq "import $prerequisite" "$work/c1/KeriBlaster/$importer_file.lean" \
    || fail "C1 fixture does not realize chain edge $prerequisite -> $importer"
done
lexical_order="$(printf '%s\n' \
  KeriBlaster.Alpha KeriBlaster.Beta KeriBlaster.Gamma \
  | LC_ALL=C sort | paste -sd, -)"
lexical_violations="$(count_violations "$work/c1" "$lexical_order")"
(( lexical_violations > 0 )) \
  || fail "C1 fixture has no lexical violation: $lexical_violations"
if ! timeout 120 "$elaborator" \
    "$build_root" "$work/c1" "$artifact_root" "$work/c1-output" \
    "$work/c1/KeriBlaster/Alpha.lean" \
    "$work/c1/KeriBlaster/Beta.lean" \
    "$work/c1/KeriBlaster/Gamma.lean" \
    "$work/c1/KeriBlaster.lean" \
    >"$work/c1.stdout" 2>"$work/c1.stderr"; then
  cat "$work/c1.stderr" >&2
  fail 'C1 elaborator rejected the dependent-sorts-first fixture'
fi
c1_order="$(extract_order "$work/c1.stderr" 3)"
derived_violations="$(count_violations "$work/c1" "$c1_order")"
(( derived_violations == 0 )) \
  || fail "C1 derived order retains $derived_violations dependency violations"
gamma_position="$(position_of "$c1_order" KeriBlaster.Gamma)"
beta_position="$(position_of "$c1_order" KeriBlaster.Beta)"
alpha_position="$(position_of "$c1_order" KeriBlaster.Alpha)"
(( gamma_position < beta_position && beta_position < alpha_position )) \
  || fail "C1 derived order violates chain Gamma -> Beta -> Alpha: $c1_order"
(( gamma_position < alpha_position )) \
  || fail "C1 derived order violates transitive precedence Gamma -> Alpha: $c1_order"
assert_compiled "$work/c1-output" \
  KeriBlaster.Alpha KeriBlaster.Beta KeriBlaster.Gamma KeriBlaster
printf '%s\n' \
  "RED-PROOF invariant=INV-289-ORDER-DERIVED mutation=synthetic-dependent-sorts-first lexical_violations=$lexical_violations derived_violations=$derived_violations outcome=REFUTED chain_depth=$chain_depth"

# A fake compiler makes "before any elaboration" directly observable for C2
# and C3. Any attempted invocation leaves a marker and fails the control.
mkdir -p "$work/no-lean-bin"
cat <<'SH' >"$work/no-lean-bin/lean"
#!/usr/bin/env bash
set -euo pipefail
: "${ELABORATION_LEAN_MARKER:?}"
printf 'invoked\n' >"$ELABORATION_LEAN_MARKER"
exit 99
SH
chmod +x "$work/no-lean-bin/lean"

# C2: an absent declared local import fails with its own layer before Lean.
mkdir -p "$work/c2/KeriBlaster" "$work/c2-output"
cat <<'LEAN' >"$work/c2/KeriBlaster/Beta.lean"
import KeriBlaster.MissingPrerequisite
def betaValue : Nat := 10
LEAN
cat <<'LEAN' >"$work/c2/KeriBlaster.lean"
import KeriBlaster.Beta
LEAN
c2_rc=0
ELABORATION_LEAN_MARKER="$work/c2-lean-invoked" \
PATH="$work/no-lean-bin:$PATH" \
  timeout 120 "$elaborator" \
    "$build_root" "$work/c2" "$artifact_root" "$work/c2-output" \
    "$work/c2/KeriBlaster/Beta.lean" \
    "$work/c2/KeriBlaster.lean" \
    >"$work/c2.stdout" 2>"$work/c2.stderr" || c2_rc=$?
(( c2_rc != 0 )) || fail 'C2 elaborator accepted an unresolved local import'
[[ ! -e $work/c2-lean-invoked ]] \
  || fail 'C2 invoked Lean after detecting an unresolved local import'
[[ -z $(find "$work/c2-output" -mindepth 1 -print -quit) ]] \
  || fail 'C2 produced output despite an unresolved local import'
missing_layer="$(sed -nE \
  's/.*outcome=COULD-NOT-EVALUATE layer=([a-z0-9-]+).*/\1/p' \
  "$work/c2.stderr" | head -1)"
[[ -n $missing_layer && $missing_layer != build-root-provenance ]] \
  || fail "C2 did not emit a distinct failure layer: ${missing_layer:-absent}"
printf '%s\n' \
  "RED-PROOF invariant=INV-289-MISSING-DEP-FAILS-CLOSED mutation=unresolved-local-import layer=$missing_layer outcome=REFUTED"

# C3: a cycle fails with another layer, names both participants, and never
# reaches Lean.
mkdir -p "$work/c3/KeriBlaster" "$work/c3-output"
cat <<'LEAN' >"$work/c3/KeriBlaster/CycleA.lean"
import KeriBlaster.CycleB
def cycleAValue : Nat := 100
LEAN
cat <<'LEAN' >"$work/c3/KeriBlaster/CycleB.lean"
import KeriBlaster.CycleA
def cycleBValue : Nat := 200
LEAN
cat <<'LEAN' >"$work/c3/KeriBlaster.lean"
import KeriBlaster.CycleA
import KeriBlaster.CycleB
LEAN
c3_rc=0
ELABORATION_LEAN_MARKER="$work/c3-lean-invoked" \
PATH="$work/no-lean-bin:$PATH" \
  timeout 120 "$elaborator" \
    "$build_root" "$work/c3" "$artifact_root" "$work/c3-output" \
    "$work/c3/KeriBlaster/CycleA.lean" \
    "$work/c3/KeriBlaster/CycleB.lean" \
    "$work/c3/KeriBlaster.lean" \
    >"$work/c3.stdout" 2>"$work/c3.stderr" || c3_rc=$?
(( c3_rc != 0 )) || fail 'C3 elaborator accepted a dependency cycle'
[[ ! -e $work/c3-lean-invoked ]] \
  || fail 'C3 invoked Lean after detecting a dependency cycle'
[[ -z $(find "$work/c3-output" -mindepth 1 -print -quit) ]] \
  || fail 'C3 produced output despite a dependency cycle'
cycle_layer="$(sed -nE \
  's/.*outcome=COULD-NOT-EVALUATE layer=([a-z0-9-]+).*/\1/p' \
  "$work/c3.stderr" | head -1)"
[[ -n $cycle_layer && $cycle_layer != build-root-provenance ]] \
  || fail "C3 did not emit a distinct failure layer: ${cycle_layer:-absent}"
[[ $cycle_layer != "$missing_layer" ]] \
  || fail "C2 and C3 share failure layer $cycle_layer"
grep -Fq 'KeriBlaster/CycleA.lean' "$work/c3.stderr" \
  || fail 'C3 diagnostic omits CycleA'
grep -Fq 'KeriBlaster/CycleB.lean' "$work/c3.stderr" \
  || fail 'C3 diagnostic omits CycleB'
printf '%s\n' \
  "RED-PROOF invariant=INV-289-CYCLE-FAILS-CLOSED mutation=dependency-cycle layer=$cycle_layer outcome=REFUTED"

# C4: four permutations of one input set must produce one exact order.
mkdir -p "$work/c4/KeriBlaster"
cat <<'LEAN' >"$work/c4/KeriBlaster/M1.lean"
import KeriBlaster.M3
def m1Value : Nat := 1
LEAN
cat <<'LEAN' >"$work/c4/KeriBlaster/M2.lean"
import KeriBlaster.M3
def m2Value : Nat := 2
LEAN
cat <<'LEAN' >"$work/c4/KeriBlaster/M3.lean"
def m3Value : Nat := 3
LEAN
cat <<'LEAN' >"$work/c4/KeriBlaster/M4.lean"
def m4Value : Nat := 4
LEAN
cat <<'LEAN' >"$work/c4/KeriBlaster.lean"
import KeriBlaster.M1
import KeriBlaster.M2
import KeriBlaster.M3
import KeriBlaster.M4
LEAN
c4_files=(
  "$work/c4/KeriBlaster/M1.lean"
  "$work/c4/KeriBlaster/M2.lean"
  "$work/c4/KeriBlaster/M3.lean"
  "$work/c4/KeriBlaster/M4.lean"
  "$work/c4/KeriBlaster.lean"
)
declare -a orders=()
for permutation in 1 2 3 4; do
  mkdir -p "$work/c4-output-$permutation"
  case "$permutation" in
    1) files=("${c4_files[0]}" "${c4_files[1]}" "${c4_files[2]}" "${c4_files[3]}" "${c4_files[4]}") ;;
    2) files=("${c4_files[3]}" "${c4_files[2]}" "${c4_files[1]}" "${c4_files[0]}" "${c4_files[4]}") ;;
    3) files=("${c4_files[1]}" "${c4_files[3]}" "${c4_files[0]}" "${c4_files[2]}" "${c4_files[4]}") ;;
    4) files=("${c4_files[2]}" "${c4_files[0]}" "${c4_files[3]}" "${c4_files[1]}" "${c4_files[4]}") ;;
  esac
  if ! timeout 120 "$elaborator" \
      "$build_root" "$work/c4" "$artifact_root" "$work/c4-output-$permutation" \
      "${files[@]}" \
      >"$work/c4-$permutation.stdout" 2>"$work/c4-$permutation.stderr"; then
    cat "$work/c4-$permutation.stderr" >&2
    fail "C4 elaborator rejected permutation $permutation"
  fi
  orders+=("$(extract_order "$work/c4-$permutation.stderr" 4)")
  assert_compiled "$work/c4-output-$permutation" \
    KeriBlaster.M1 KeriBlaster.M2 KeriBlaster.M3 KeriBlaster.M4 KeriBlaster
done
distinct_orders="$(printf '%s\n' "${orders[@]}" | LC_ALL=C sort -u | grep -c .)"
(( distinct_orders == 1 )) \
  || fail "C4 observed $distinct_orders orders across ${#orders[@]} permutations"
printf '%s\n' \
  "RED-PROOF invariant=INV-289-ORDER-DETERMINISTIC mutation=permuted-argument-order permutations=${#orders[@]} distinct_orders=$distinct_orders outcome=REFUTED"

# Finally exercise the exact tracked set that motivated this slice.
declare -a tracked_sources=()
mapfile -d '' tracked_sources < <(
  find "$source_root/KeriBlaster" -type f -name '*.lean' -print0
)
tracked_count=${#tracked_sources[@]}
(( tracked_count > 0 )) || fail 'tracked source set is empty'
tracked_sources+=("$source_root/KeriBlaster.lean")
mkdir -p "$work/tracked-output"
if ! timeout 120 "$elaborator" \
    "$build_root" "$source_root" "$artifact_root" "$work/tracked-output" \
    "${tracked_sources[@]}" \
    >"$work/tracked.stdout" 2>"$work/tracked.stderr"; then
  cat "$work/tracked.stderr" >&2
  fail 'tracked source set could not be elaborated'
fi
tracked_order="$(extract_order "$work/tracked.stderr" "$tracked_count")"
tracked_violations="$(count_violations "$source_root" "$tracked_order")"
(( tracked_violations == 0 )) \
  || fail "tracked derived order retains $tracked_violations dependency violations"
assert_compiled "$work/tracked-output" KeriBlaster

printf 'PASS: elaboration order derived from declared imports over %d synthetic and %d tracked modules\n' \
  12 "$tracked_count"
