#!/usr/bin/env bash
# Bind a verdict to the published bytes. Expected COMMIT + VARIANT come
# from the producer pins (or the checkout's source identity), never from
# the bytes under test. A second conforming parse of any identity field
# is RED.
set -euo pipefail

usage() { echo "usage: $0 BYTES" >&2; exit 2; }
[ "$#" -eq 1 ] || usage
bytes=$1
coverage_token=parsed-document
expected_variant=defaultFunSemanticsVariantE

[ -r "$bytes" ] || {
  echo "published bytes unreadable: $bytes" >&2
  exit 1
}

if [ "$(head -c 3 "$bytes" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
  echo "AUDIT-SELFTEST leg=artifact-not-bound-to-verdict rc=1 outcome=REFUTED"
  echo "published bytes carry a UTF-8 BOM; document parse is not the bytes" >&2
  exit 1
fi

first_value() {
  local field=$1 line
  # grep -m1, not grep|head: a real manifest repeats identity keys
  # on every record, and pipefail turns that SIGPIPE into a silent 141.
  line=$(grep -oEm1 \
    "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" "$bytes" || true)
  [ -n "$line" ] || return 0
  sed 's/.*"\([^"]*\)"$/\1/' <<<"$line"
}

for field in variant commit aiken toolchain; do
  last=$(jq -r --arg f "$field" '.identity[$f] // empty' "$bytes")
  first=$(first_value "$field")
  if [ -n "$first" ] && [ "$last" != "$first" ]; then
    echo "AUDIT-SELFTEST leg=second-conforming-parse-differs rc=1 outcome=REFUTED"
    echo "second conforming parse differs: field=$field last_wins=$last first_wins=$first" >&2
    exit 1
  fi
done

variant=$(jq -r '.identity.variant // empty' "$bytes")
commit=$(jq -r '.identity.commit // empty' "$bytes")

if [ "$variant" != "$expected_variant" ]; then
  echo "AUDIT-SELFTEST leg=artifact-not-bound-to-verdict rc=1 outcome=REFUTED"
  echo "published identity variant is not $expected_variant" >&2
  exit 1
fi

expected_commit=${CKERI_EXPECTED_COMMIT:-}
if [ -z "$expected_commit" ]; then
  script_repo=$(cd "$(dirname "$0")/../.." && pwd)
  if git -C "$script_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1
  then
    expected_commit=$(git -C "$script_repo" rev-parse HEAD)
  elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    expected_commit=$(git rev-parse HEAD)
  else
    echo "published identity commit cannot be resolved: no producer pin and no git source identity" >&2
    exit 1
  fi
fi

if [ -z "$commit" ] || [ "$commit" != "$expected_commit" ]; then
  echo "AUDIT-SELFTEST leg=artifact-not-bound-to-verdict rc=1 outcome=REFUTED"
  echo "published identity commit is not the source identity" >&2
  exit 1
fi

digest=$(sha256sum "$bytes" | cut -d ' ' -f 1)
echo "AUDIT-ARTIFACT-BINDING digest=$digest instrument=sha256sum window=published-bytes coverage=$coverage_token outcome=ESTABLISHED"
exit 0
