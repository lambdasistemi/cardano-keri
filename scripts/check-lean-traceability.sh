#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
csv="$repo_root/lean/traceability.csv"
goals="$repo_root/lean/CardanoKeri/Goals.lean"
haskell_spec="$repo_root/offchain/test/Cardano/KERI/AID/Checkpoint/LifecycleModelSpec.hs"
aiken_tests="$repo_root/onchain/lib/cardano_keri/checkpoint/lifecycle_model_tests.ak"

expected_comments=(
  '# Lean proves universal claims over the abstract lifecycle model.'
  '# QuickCheck samples the pure Haskell lifecycle mirror.'
  '# Generated parity vectors bind Haskell verdicts to Aiken verdicts.'
  '# Full-context Aiken tests cover abstracted ledger details (address, datum, and real Value arithmetic); no refinement proof is claimed.'
)

mapfile -t actual_comments < <(sed -n '1,4p' "$csv")
[[ ${#actual_comments[@]} -eq 4 ]] || {
  printf 'traceability: expected exactly four leading comment statements\n' >&2
  exit 1
}
for index in 0 1 2 3; do
  [[ ${actual_comments[$index]} == "${expected_comments[$index]}" ]] || {
    printf 'traceability: malformed comment %s\n' "$((index + 1))" >&2
    exit 1
  }
done

header=$(sed -n '5p' "$csv")
[[ $header == 'lean_theorem,quickcheck_property,aiken_test' ]] || {
  printf 'traceability: malformed CSV header\n' >&2
  exit 1
}

mapfile -t source_theorems < <(
  awk '/^theorem[[:space:]]+/ { print $2 }' "$goals"
)
[[ ${#source_theorems[@]} -eq 21 ]] || {
  printf 'traceability: Goals.lean declares %s theorems, expected 21\n' "${#source_theorems[@]}" >&2
  exit 1
}

mapfile -t rows < <(sed -n '6,$p' "$csv")
[[ ${#rows[@]} -eq 21 ]] || {
  printf 'traceability: map has %s data rows, expected 21\n' "${#rows[@]}" >&2
  exit 1
}

for row in "${rows[@]}"; do
  [[ -n $row ]] || {
    printf 'traceability: blank row\n' >&2
    exit 1
  }
  awk -F, '
    NF != 3 || $1 == "" || $2 == "" || $3 == "" { exit 1 }
  ' <<<"$row" || {
    printf 'traceability: malformed or incomplete row: %s\n' "$row" >&2
    exit 1
  }
done

mapfile -t mapped_theorems < <(printf '%s\n' "${rows[@]}" | awk -F, '{ print $1 }')
mapfile -t mapped_properties < <(printf '%s\n' "${rows[@]}" | awk -F, '{ print $2 }')
mapfile -t mapped_tests < <(printf '%s\n' "${rows[@]}" | awk -F, '{ print $3 }')

for index in "${!source_theorems[@]}"; do
  [[ ${mapped_theorems[$index]} == "${source_theorems[$index]}" ]] || {
    printf 'traceability: source-order drift at row %s: expected %s, found %s\n' \
      "$((index + 1))" "${source_theorems[$index]}" "${mapped_theorems[$index]}" >&2
    exit 1
  }
done

for column_name in theorem property test; do
  case $column_name in
    theorem) values=("${mapped_theorems[@]}") ;;
    property) values=("${mapped_properties[@]}") ;;
    test) values=("${mapped_tests[@]}") ;;
  esac
  # PENDING(#N) sentinels stand in for tests the paused #114/#115/#117 pipeline
  # will deliver; they legitimately repeat across rows, so exempt them.
  duplicate=$(printf '%s\n' "${values[@]}" | grep -v '^PENDING(' | sort | uniq -d | sed -n '1p')
  [[ -z $duplicate ]] || {
    printf 'traceability: duplicate %s identifier: %s\n' "$column_name" "$duplicate" >&2
    exit 1
  }
done

for index in "${!mapped_theorems[@]}"; do
  property_name=${mapped_properties[$index]}
  test_name=${mapped_tests[$index]}
  # PENDING(#N): the paused pipeline owns the test; skip the existence check but
  # keep the theorem mapped (still hard-fails on an unmapped Goals.lean theorem).
  if [[ $property_name != PENDING\(*\) ]]; then
    rg -q "^${property_name} :: Property$" "$haskell_spec" || {
      printf 'traceability: missing Haskell property %s\n' "$property_name" >&2
      exit 1
    }
  fi
  if [[ $test_name != PENDING\(*\) ]]; then
    rg -q "^test ${test_name}\\(\\)" "$aiken_tests" || {
      printf 'traceability: missing Aiken test %s\n' "$test_name" >&2
      exit 1
    }
  fi
done

cd "$repo_root"
just check-lifecycle-trace-vectors
printf 'traceability: 21 Lean theorems mapped to executable Haskell/Aiken identifiers (PENDING(#127-pipeline) rows await the paused #114/#115/#117 tests)\n'
