#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

deploy_transcript="${1:-deploy/preprod/m1-board-deploy-verify-acceptance.txt}"
post_transcript="${2:-deploy/preprod/m1-board-operator-post-acceptance.txt}"
stranger_transcript="${3:-deploy/preprod/m1-board-stranger-acceptance.txt}"
lifecycle_transcript="${4:-deploy/preprod/m1-board-operator-lifecycle-acceptance.txt}"
manifest="${5:-deploy/preprod/board-manifest.json}"
refund_address='addr_test1qzdqjmt98smx8my6f5uum0szghuy8ff2hep2e64a9w2pehty436vwj3d2cslvu2a4aypkrqa4d6ujvldn8l6utg5yyqs4pqv6d'

transcripts=(
  "$deploy_transcript"
  "$post_transcript"
  "$stranger_transcript"
  "$lifecycle_transcript"
)
total_bytes=0
for transcript in "${transcripts[@]}"; do
  if test "$(tr -d '\000' <"$transcript" | wc -c)" -ne \
    "$(wc -c <"$transcript")" ||
    grep -q $'\r' "$transcript" ||
    grep -q $'\033' "$transcript"; then
    echo "board transcripts must be plain captured text: $transcript" >&2
    exit 1
  fi
  grep -q '^[$] ' "$transcript"
  if grep -Fq 'cardano-cli' "$transcript"; then
    echo "board transcript still invokes cardano-cli: $transcript" >&2
    exit 1
  fi
  total_bytes="$((total_bytes + $(wc -c <"$transcript")))"
done
test "$total_bytes" -lt 60000

post_date="$(sed -n 's/^\(2026-[0-9T:Z-]*\)$/\1/p' "$post_transcript" | head -1)"
stranger_date="$(sed -n 's/^\(2026-[0-9T:Z-]*\)$/\1/p' "$stranger_transcript" | head -1)"
lifecycle_date="$(sed -n 's/^\(2026-[0-9T:Z-]*\)$/\1/p' "$lifecycle_transcript" | head -1)"
deploy_date="$(sed -n 's/^\(2026-[0-9T:Z-]*\)$/\1/p' "$deploy_transcript" | head -1)"
test "$post_date" \< "$stranger_date"
test "$stranger_date" \< "$lifecycle_date"
test "$lifecycle_date" \< "$deploy_date"

schema="$(jq -r .schema "$manifest")"
policy="$(jq -r .board.policyId "$manifest")"
board_address="$(jq -r .board.address "$manifest")"
reference_txid="$(jq -r .board.reference.txId "$manifest")"
reference_index="$(jq -r .board.reference.index "$manifest")"
test "$schema" = 'cardano-keri/m1-endpoint-board-manifest/v1'
test "$policy" = '54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c'
test "$board_address" = 'addr_test1wp2yjnu2rv5nqfqm0w06qy8kruk0vvra42l6k600h7gjzrqpd4hm4'
test "$reference_txid" = '967b86211ab7c80876ae4b6bec0e478dd92a98f14d5c3d751a99ad01c04654d4'
test "$reference_index" -eq 0

grep -Fqx 'deployment mode: verify-only (no reference publication)' "$deploy_transcript"
test "$(grep -c '^expected reference ' "$deploy_transcript")" -eq 5
test "$(grep -c '^live reference ' "$deploy_transcript")" -eq 5
while read -r hash out_ref; do
  grep -Eq "^expected reference [^ ]+ $hash $out_ref$" "$deploy_transcript"
  grep -Fqx "live reference $hash $out_ref" "$deploy_transcript"
done < <(
  jq -r '.scripts[] | [.hash, (.reference.txId + "#" + (.reference.index | tostring))] | @tsv' \
    deploy/preprod/m1-manifest.json
)
grep -Fqx "board reference: $policy $reference_txid#$reference_index" "$deploy_transcript"

post_txid="$(
  sed -n 's/^board txid: \([0-9a-f]\{64\}\) deposit: 4 tADA$/\1/p' \
    "$post_transcript"
)"
[[ "$post_txid" =~ ^[0-9a-f]{64}$ ]]
test "$(grep -c '^board records: 3$' "$post_transcript")" -eq 1
test "$(grep -c '^board records: 4$' "$post_transcript")" -eq 1
grep -Fq "$post_txid#0 deposit 4000000" "$post_transcript"
grep -Fqx 'HTTP 200 bytes 1239' "$stranger_transcript"
grep -Fqx 'board records: 4' "$stranger_transcript"
grep -Fq "$post_txid#0 deposit 4000000" "$stranger_transcript"

update_txid="$(
  sed -n 's/^board update txid: \([0-9a-f]\{64\}\)$/\1/p' \
    "$lifecycle_transcript"
)"
retire_txid="$(
  sed -n 's/^board retire txid: \([0-9a-f]\{64\}\)$/\1/p' \
    "$lifecycle_transcript"
)"
[[ "$update_txid" =~ ^[0-9a-f]{64}$ ]]
[[ "$retire_txid" =~ ^[0-9a-f]{64}$ ]]
test "$post_txid" != "$update_txid"
test "$post_txid" != "$retire_txid"
test "$update_txid" != "$retire_txid"
grep -Fqx "replaced: $post_txid#0" "$lifecycle_transcript"
grep -Fq "$update_txid#0 deposit 4000000" "$lifecycle_transcript"
grep -Fqx "refunded: 4 tADA to $refund_address" "$lifecycle_transcript"
test "$(grep -c '^board records: 4$' "$lifecycle_transcript")" -eq 1
test "$(grep -c '^board records: 3$' "$lifecycle_transcript")" -eq 1

post_line="$(grep -nF "board txid: $post_txid" "$post_transcript" | cut -d: -f1)"
post_four_line="$(grep -n '^board records: 4$' "$post_transcript" | cut -d: -f1)"
update_line="$(grep -nF "board update txid: $update_txid" "$lifecycle_transcript" | cut -d: -f1)"
lifecycle_four_line="$(grep -n '^board records: 4$' "$lifecycle_transcript" | cut -d: -f1)"
retire_line="$(grep -nF "board retire txid: $retire_txid" "$lifecycle_transcript" | cut -d: -f1)"
lifecycle_three_line="$(grep -n '^board records: 3$' "$lifecycle_transcript" | cut -d: -f1)"
test "$post_line" -lt "$post_four_line"
test "$update_line" -lt "$lifecycle_four_line"
test "$lifecycle_four_line" -lt "$retire_line"
test "$retire_line" -lt "$lifecycle_three_line"

original_out_refs=(
  '0d130e108d6b3c1193c6fa6bf5f63e0474bef5b0c0be1ba95e2cf90c5410b1f9#0'
  '5e705ac1f08aee4119a52fe890e040b6fb4f716603598ee3eaf0027201e4a526#0'
  'a01062724b678b988d294f1a7d352ee13fa8fc7c682340d61f89911364e2a365#0'
)
final_lifecycle="$(sed -n '/^board records: 3$/,$p' "$lifecycle_transcript")"
for out_ref in "${original_out_refs[@]}"; do
  grep -Fq "$out_ref deposit 4000000" <<<"$final_lifecycle"
  grep -Fq "$out_ref deposit 4000000" "$deploy_transcript"
done
test "$(grep -c ' verified https .* deposit 4000000$' <<<"$final_lifecycle")" -eq 3
test "$(grep -c ' verified https .* deposit 4000000$' "$deploy_transcript")" -eq 3
if grep -Eq "($post_txid|$update_txid)#0" <<<"$final_lifecycle"; then
  echo 'retired temporary board record survives in final lifecycle listing' >&2
  exit 1
fi

if [[ -n "${CKERI_BIN:-}" ]]; then
  final_board="$("$CKERI_BIN" board list --board-manifest "$manifest")"
  grep -Fqx 'board records: 3' <<<"$final_board"
  for out_ref in "${original_out_refs[@]}"; do
    grep -Fq "$out_ref deposit 4000000" <<<"$final_board"
  done
  payload="$(
    jq -cn \
      --arg post "$post_txid" \
      --arg update "$update_txid" \
      --arg retire "$retire_txid" \
      '{_tx_hashes: [$post, $update, $retire]}'
  )"
  tx_info="$(curl --fail --silent --show-error --request POST \
    https://preprod.koios.rest/api/v1/tx_info \
    --header 'Content-Type: application/json' --data "$payload")"
  jq -e 'length == 3 and all(.[]; .block_hash != null)' <<<"$tx_info" >/dev/null
  echo 'M1 in-process board lifecycle and deploy verification are live: OK'
else
  echo 'M1 in-process board transcripts are internally consistent: OK'
fi
