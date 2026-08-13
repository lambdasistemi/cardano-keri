#!/usr/bin/env bash
# Bind a verdict to the published bytes and reject a second conforming
# parse that yields a different identity (duplicate keys, BOM prefix).
set -euo pipefail

usage() { echo "usage: $0 BYTES" >&2; exit 2; }
[ "$#" -eq 1 ] || usage
bytes=$1
coverage_token=parsed-document

[ -r "$bytes" ] || {
  echo "published bytes unreadable: $bytes" >&2
  exit 1
}

if [ "$(head -c 3 "$bytes" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
  echo "AUDIT-SELFTEST leg=artifact-not-bound-to-verdict rc=1 outcome=REFUTED"
  echo "published bytes carry a UTF-8 BOM; document parse is not the bytes" >&2
  exit 1
fi

parsed_last=$(jq -er '.identity.variant' "$bytes")
parsed_first=$(grep -oE '"variant"[[:space:]]*:[[:space:]]*"[^"]+"' "$bytes" \
  | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ -z "$parsed_first" ] || [ "$parsed_last" != "$parsed_first" ]; then
  echo "AUDIT-SELFTEST leg=second-conforming-parse-differs rc=1 outcome=REFUTED"
  echo "second conforming parse differs: last_wins=$parsed_last first_wins=${parsed_first:-<none>}" >&2
  exit 1
fi

digest=$(sha256sum "$bytes" | cut -d ' ' -f 1)
echo "AUDIT-ARTIFACT-BINDING digest=$digest instrument=sha256sum window=published-bytes coverage=$coverage_token outcome=ESTABLISHED"
exit 0
