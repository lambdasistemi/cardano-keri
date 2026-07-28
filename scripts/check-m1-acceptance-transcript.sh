#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

manifest="${1:-deploy/preprod/m1-manifest.json}"
transcript="${2:-deploy/preprod/m1-acceptance.txt}"

if grep -q $'\r' "$transcript" || grep -q $'\033' "$transcript"; then
  echo "acceptance transcript must be plain captured text" >&2
  exit 1
fi

source_commit="$(
  jq -er '
    .source.commit
    | select(type == "string" and test("^[0-9a-f]{40}$"))
  ' "$manifest"
)"
script_count="$(jq -er '.scripts | length' "$manifest")"

grep -Fqx '$ git rev-parse HEAD' "$transcript"
grep -Fqx "$source_commit" "$transcript"
grep -Eq \
  "^\\$ .*[/]ckeri deploy .*--source-commit ${source_commit} .*--out deploy/preprod/m1-manifest\\.json" \
  "$transcript"
grep -Eq \
  '^[$] .*[/]ckeri manifest verify --manifest deploy/preprod/m1-manifest\.json --source-repo \.$' \
  "$transcript"
grep -Fqx "source rebuild: OK commit=$source_commit" "$transcript"

while IFS=$'\t' read -r name hash tx_id index; do
  grep -Fqx \
    "deployed $name hash=$hash reference=$tx_id#$index" \
    "$transcript"
  grep -Fqx "hash $name: OK $hash" "$transcript"
  grep -Fqx "on-chain $name: OK $tx_id#$index" "$transcript"
done < <(
  jq -er '
    .scripts[]
    | [.name, .hash, .reference.txId, (.reference.index | tostring)]
    | @tsv
  ' "$manifest"
)

test "$(grep -c '^deployed ' "$transcript")" -eq "$script_count"
test "$(grep -c '^hash .*: OK ' "$transcript")" -eq "$script_count"
test "$(grep -c '^on-chain .*: OK ' "$transcript")" -eq "$script_count"
grep -Fqx \
  'manifest verify: OK — rebuilt from source; all hashes and on-chain references are live' \
  "$transcript"

echo "M1 captured acceptance transcript matches the manifest: OK"
