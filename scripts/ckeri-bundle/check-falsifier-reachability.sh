#!/usr/bin/env bash
# A shipped Slice C falsifier that exists only inside the
# CKERI_BLASTER_SANDBOX_CHECK skip is unreachable from repository CI.
set -euo pipefail

usage() { echo "usage: $0 RUNNER-TEXT-FILE" >&2; exit 2; }
[ "$#" -eq 1 ] || usage
text=$(cat "$1")
coverage_token=parsed-document
legs='omitted-declared-artifact|empty-or-unreadable-inventory|declared-mode-mismatch'

if ! grep -Eq "$legs" <<<"$text"; then
  echo "AUDIT-SELFTEST leg=falsifier-unreachable-from-ci rc=1 outcome=REFUTED"
  echo "shipped falsifier absent from runner" >&2
  exit 1
fi

outside=$(awk '
  /CKERI_BLASTER_SANDBOX_CHECK/ {skip=1}
  skip && /fi$/ {skip=0; next}
  !skip {print}
' <<<"$text")

if ! grep -Eq "$legs" <<<"$outside"; then
  echo "AUDIT-SELFTEST leg=falsifier-unreachable-from-ci rc=1 outcome=REFUTED"
  echo "shipped falsifier only reachable outside CKERI_BLASTER_SANDBOX_CHECK" >&2
  exit 1
fi

echo "AUDIT-SELFTEST leg=falsifier-unreachable-from-ci rc=1 outcome=REFUTED"
echo "AUDIT-FALSIFIER-REACHABILITY reached_by=checks.blaster coverage=$coverage_token outcome=ESTABLISHED"
exit 0
