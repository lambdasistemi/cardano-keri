#!/usr/bin/env bash
# S0-F10 — refuse missing or unreachable role obligations.
set -euo pipefail

root=${1:?usage: check-skeleton-obligations.sh SOURCE_ROOT [MANIFEST]}
if [[ $# -ge 2 ]]; then
  manifest=$2
else
  manifest=$(cd "$(dirname "$0")" && pwd)/obligations.manifest
fi

if [[ ! -f "$manifest" ]]; then
  printf 'ANTI-STUB-FAIL obligation=S0-F10 reason=missing-manifest path=%s\n' \
    "$manifest" >&2
  exit 42
fi

failures=0
checks=0

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
  if ! sed -E '/^[[:space:]]*\/\//d' "$file" | grep -Eq "$pattern"; then
    printf 'ANTI-STUB-FAIL obligation=%s reason=missing-reachable-surface path=%s pattern=%s\n' \
      "$obligation" "$relative" "$pattern" >&2
    failures=$((failures + 1))
  fi
done <"$manifest"

if (( failures > 0 )); then
  printf 'ANTI-STUB-REJECT checks=%d failures=%d source_root=%s\n' \
    "$checks" "$failures" "$root" >&2
  exit 42
fi

printf 'ANTI-STUB-PASS checks=%d failures=0 source_root=%s\n' "$checks" "$root"
