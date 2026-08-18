#!/usr/bin/env bash
# S0-F10 — supplementary static completeness map. Reachability is
# scripts/s0/check-reachability.sh.
set -euo pipefail

root=${1:?usage: check-skeleton-obligations.sh SOURCE_ROOT [MANIFEST]}
here=$(cd "$(dirname "$0")" && pwd)
if [[ $# -ge 2 ]]; then
  manifest=$2
else
  manifest=$here/obligations.manifest
fi
contract_map=$here/contract-map.tsv
modules=$root/specs/m11-s0-size-failfast/modules-model.md

if [[ ! -f "$manifest" ]]; then
  printf 'ANTI-STUB-FAIL obligation=S0-F10 reason=missing-manifest path=%s\n' \
    "$manifest" >&2
  exit 42
fi
if [[ ! -f "$contract_map" ]]; then
  printf 'ANTI-STUB-FAIL obligation=S0-F10 reason=missing-contract-map path=%s\n' \
    "$contract_map" >&2
  exit 42
fi
if [[ ! -f "$modules" ]]; then
  printf 'ANTI-STUB-FAIL obligation=S0-F10 reason=missing-modules-model path=%s\n' \
    "$modules" >&2
  exit 42
fi

failures=0
checks=0

# Every S0-M0N row in the modules model must appear in the contract map.
while read -r mid; do
  checks=$((checks + 1))
  if ! awk -F '\t' -v id="$mid" '
    $0 ~ /^#/ { next }
    $2 == id { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$contract_map"; then
    printf 'ANTI-STUB-FAIL obligation=S0-CONTRACT-COVERAGE reason=missing-module module=%s\n' \
      "$mid" >&2
    failures=$((failures + 1))
  fi
done < <(command grep -oE 'S0-M[0-9]+' "$modules" | sort -u)

# Every contract-map obligation_id must exist in the source manifest.
while IFS=$'\t' read -r _clause _mod _phrase ob; do
  [[ -z "${_clause:-}" || "$_clause" == \#* ]] && continue
  checks=$((checks + 1))
  if ! awk -F '\t' -v id="$ob" '
    $0 ~ /^#/ { next }
    $1 == id { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$manifest"; then
    printf 'ANTI-STUB-FAIL obligation=S0-CONTRACT-COVERAGE reason=orphan-clause obligation=%s\n' \
      "$ob" >&2
    failures=$((failures + 1))
  fi
done <"$contract_map"

# Every manifest obligation must be named by the contract map.
while IFS=$'\t' read -r obligation _path _pat; do
  [[ -z "${obligation:-}" || "$obligation" == \#* ]] && continue
  checks=$((checks + 1))
  if ! awk -F '\t' -v id="$obligation" '
    $0 ~ /^#/ { next }
    $4 == id { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$contract_map"; then
    printf 'ANTI-STUB-FAIL obligation=S0-CONTRACT-COVERAGE reason=implementation-only obligation=%s\n' \
      "$obligation" >&2
    failures=$((failures + 1))
  fi
done <"$manifest"

while IFS=$'\t' read -r obligation relative pattern; do
  [[ -z "${obligation:-}" || "$obligation" == \#* ]] && continue
  checks=$((checks + 1))
  file="$root/$relative"
  if [[ ! -f "$file" ]]; then
    printf 'ANTI-STUB-FAIL obligation=%s reason=missing-file path=%s\n' \
      "$obligation" "$relative" >&2
    failures=$((failures + 1))
    continue
  fi
  if ! sed -E '/^[[:space:]]*\/\//d' "$file" | command grep -E "$pattern" >/dev/null; then
    printf 'ANTI-STUB-FAIL obligation=%s reason=missing-reachable-surface path=%s pattern=%s\n' \
      "$obligation" "$relative" "$pattern" >&2
    failures=$((failures + 1))
  fi
done <"$manifest"

if ((failures > 0)); then
  printf 'ANTI-STUB-REJECT checks=%d failures=%d source_root=%s\n' \
    "$checks" "$failures" "$root" >&2
  exit 42
fi

printf 'ANTI-STUB-PASS checks=%d failures=0 source_root=%s\n' "$checks" "$root"
