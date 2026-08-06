#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

deploy_transcript="${1:-deploy/preprod/m1-board-deploy-verify-acceptance.txt}"
post_transcript="${2:-deploy/preprod/m1-board-operator-post-acceptance.txt}"
stranger_transcript="${3:-deploy/preprod/m1-board-stranger-acceptance.txt}"
lifecycle_transcript="${4:-deploy/preprod/m1-board-operator-lifecycle-acceptance.txt}"
manifest="${5:-deploy/preprod/board-manifest.json}"
clean_client_transcript="${6:-deploy/preprod/m1-board-clean-client-historical-acceptance.txt}"
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

# Preserve the independent clean-client seat: a fresh Nix host cloned the
# public repository and ran its packaged app. The current stranger transcript
# observes the temporary record through the repaired local artifact; it is not
# substituted for this clean-client property.
if grep -q $'\r' "$clean_client_transcript" || grep -q $'\033' "$clean_client_transcript"; then
  echo "historical board clean-client capture must be plain text" >&2
  exit 1
fi
grep -Fqx '$ hostname -f' "$clean_client_transcript"
grep -Fqx 'zur1-s-d-030.colo1.cf-systems.internal' "$clean_client_transcript"
grep -Fqx '$ test '\''!'\'' -e /code/cardano-keri-165-stranger-final' "$clean_client_transcript"
grep -Fqx \
  '$ git clone --filter=blob:none --branch story/165-endpoint-board --single-branch https://github.com/lambdasistemi/cardano-keri /code/cardano-keri-165-stranger-final' \
  "$clean_client_transcript"
grep -Fqx \
  '$ nix shell nixpkgs#nix -c nix run --accept-flake-config --quiet ./offchain#ckeri -- board list --board-manifest deploy/preprod/board-manifest.json' \
  "$clean_client_transcript"
grep -Fqx 'board records: 3' "$clean_client_transcript"
grep -Fqx 'HTTP_200_bytes_1239n' "$clean_client_transcript"
if grep -Fq '/code/cardano-keri-181-txpath' "$clean_client_transcript"; then
  echo "board clean-client proof unexpectedly references the local Slice 4 checkout" >&2
  exit 1
fi

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
  curl_args=(--fail --silent --show-error)
  if [[ -n "${KOIOS_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: Bearer $KOIOS_TOKEN")
  fi
  tx_info="$(curl "${curl_args[@]}" --request POST \
    https://preprod.koios.rest/api/v1/tx_info \
    --header 'Content-Type: application/json' --data "$payload")"
  jq -e 'length == 3 and all(.[]; .block_hash != null)' <<<"$tx_info" >/dev/null
  echo 'M1 in-process board lifecycle is live and the independent public-repo clean-client proof is preserved: OK'
else
  echo 'M1 board journey and independent public-repo clean-client proof are internally consistent: OK'
fi

# Every assertion below is preserved verbatim from the accepted base and
# deliberately bound to that journey's own historical artifacts. The
# regenerated single-post primary journey above remains independently checked.
check_historical_board_base_assertions() (
  deploy_transcript=deploy/preprod/m1-board-deploy-verify-historical-acceptance.txt
  post_transcript=deploy/preprod/m1-board-operator-post-historical-acceptance.txt
  stranger_transcript=deploy/preprod/m1-board-clean-client-historical-acceptance.txt
  lifecycle_transcript=deploy/preprod/m1-board-operator-lifecycle-historical-negative-acceptance.txt
  manifest=deploy/preprod/board-manifest.json
  transcripts=(
    "$deploy_transcript"
    "$post_transcript"
    "$stranger_transcript"
    "$lifecycle_transcript"
  )
  for transcript in "${transcripts[@]}"; do
    if test "$(tr -d '\000' <"$transcript" | wc -c)" -ne \
      "$(wc -c <"$transcript")" ||
      grep -q $'\r' "$transcript" ||
      grep -q $'\033' "$transcript"; then
      echo "board transcripts must be plain captured text: $transcript" >&2
      exit 1
    fi
    grep -q '^\$ ' "$transcript"
  done
  total_bytes=0
  for transcript in "${transcripts[@]}"; do
    total_bytes="$((total_bytes + $(wc -c <"$transcript")))"
  done
  test "$total_bytes" -lt 60000

  grep -Fqx "production" "$post_transcript"
  grep -Fqx "production" "$lifecycle_transcript"
  grep -Fqx "production" "$deploy_transcript"
  grep -Fqx \
    "zur1-s-d-030.colo1.cf-systems.internal" \
    "$stranger_transcript"
  grep -Fqx \
    "$ test '!' -e /code/cardano-keri-165-stranger-final" \
    "$stranger_transcript"
  grep -Fqx \
    '$ git clone --filter=blob:none --branch story/165-endpoint-board --single-branch https://github.com/lambdasistemi/cardano-keri /code/cardano-keri-165-stranger-final' \
    "$stranger_transcript"
  grep -Fqx \
    '$ sed -n 32,92p docs/user/discovery-endpoint-board.md' \
    "$stranger_transcript"
  grep -Fqx "nix (Nix) 2.24.12" "$stranger_transcript"
  grep -Fqx "nix (Nix) 2.34.8" "$stranger_transcript"
  grep -Fqx \
    '$ nix shell nixpkgs#nix -c nix run --accept-flake-config --quiet ./offchain#ckeri -- board list --board-manifest deploy/preprod/board-manifest.json' \
    "$stranger_transcript"
  grep -Fqx "HTTP_200_bytes_1239n" "$stranger_transcript"

  post_date="$(
    sed -n 's/^\(2026-[0-9T:Z-]*\)$/\1/p' "$post_transcript" | head -1
  )"
  stranger_date="$(
    sed -n 's/^\(2026-[0-9T:Z-]*\)$/\1/p' "$stranger_transcript" | head -1
  )"
  lifecycle_date="$(
    sed -n 's/^\(2026-[0-9T:Z-]*\)$/\1/p' "$lifecycle_transcript" | head -1
  )"
  deploy_date="$(
    sed -n 's/^\(2026-[0-9T:Z-]*\)$/\1/p' "$deploy_transcript" | head -1
  )"
  test "$post_date" \< "$stranger_date"
  test "$stranger_date" \< "$lifecycle_date"
  test "$lifecycle_date" \< "$deploy_date"

  schema="$(jq -r .schema "$manifest")"
  policy="$(jq -r .board.policyId "$manifest")"
  board_address="$(jq -r .board.address "$manifest")"
  reference_txid="$(jq -r .board.reference.txId "$manifest")"
  reference_index="$(jq -r .board.reference.index "$manifest")"
  test "$schema" = "cardano-keri/m1-endpoint-board-manifest/v1"
  test "$policy" = \
    "54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"
  test "$board_address" = \
    "addr_test1wp2yjnu2rv5nqfqm0w06qy8kruk0vvra42l6k600h7gjzrqpd4hm4"
  test "$reference_txid" = \
    "967b86211ab7c80876ae4b6bec0e478dd92a98f14d5c3d751a99ad01c04654d4"
  test "$reference_index" -eq 0
  grep -Fq "$reference_txid" "$deploy_transcript"
  grep -Fq "$policy" "$deploy_transcript"
  grep -Fq "$board_address" "$deploy_transcript"
  grep -Fqx \
    "644,paolino,users,deploy/preprod/board-manifest.json" \
    "$deploy_transcript"

  mapfile -t post_txids < <(
    sed -n \
      's/^board txid: \([0-9a-f]\{64\}\) deposit: 4 tADA$/\1/p' \
      "$post_transcript"
  )
  test "${#post_txids[@]}" -eq 3
  test "$(
    printf '%s\n' "${post_txids[@]}" | sort -u | wc -l
  )" -eq 3
  grep -Fqx "  default: 4000000" "$post_transcript"
  test "$(grep -c '^board records: 3$' "$post_transcript")" -eq 1
  test "$(grep -c ' verified https .* deposit 4000000$' "$post_transcript")" -eq 3
  for txid in "${post_txids[@]}"; do
    grep -Fq "$txid#0" "$post_transcript"
    grep -Fq "$txid#0" "$stranger_transcript"
  done
  test "$(grep -c ' verified https .* deposit 4000000$' "$stranger_transcript")" -eq 6

  update_txid="$(
    sed -n 's/^board update txid: \([0-9a-f]\{64\}\)$/\1/p' \
      "$lifecycle_transcript"
  )"
  retire_txid="$(
    sed -n 's/^board retire txid: \([0-9a-f]\{64\}\)$/\1/p' \
      "$lifecycle_transcript"
  )"
  restore_txid="$(
    sed -n 's/^board txid: \([0-9a-f]\{64\}\) deposit: 4 tADA$/\1/p' \
      "$lifecycle_transcript"
  )"
  [[ "$update_txid" =~ ^[0-9a-f]{64}$ ]]
  [[ "$retire_txid" =~ ^[0-9a-f]{64}$ ]]
  [[ "$restore_txid" =~ ^[0-9a-f]{64}$ ]]
  test "$(
    printf '%s\n' \
      "${post_txids[@]}" \
      "$update_txid" \
      "$retire_txid" \
      "$restore_txid" |
      sort -u |
      wc -l
  )" -eq 6

  old_witness_one="${post_txids[0]}"
  for candidate in "${post_txids[@]}"; do
    if grep -Fq "replaced: ${candidate}#0" "$lifecycle_transcript"; then
      old_witness_one="$candidate"
    fi
  done
  old_witness_three="${post_txids[0]}"
  for candidate in "${post_txids[@]}"; do
    if grep -Fq \
      "BNP31dFWbqS_oUe2CUu24Ct7cQjpk3DscLzbpGT5OEz4 verified https https://witness-3.preprod.plutimus.com/ tx ${candidate}#0" \
      "$post_transcript"; then
      old_witness_three="$candidate"
    fi
  done
  grep -Fqx "FORGED_RECORD_REJECTED_OK" "$lifecycle_transcript"
  grep -Fqx \
    "user error (endpoint SAID does not bind the exact event bytes)" \
    "$lifecycle_transcript"
  grep -Fqx \
    "replaced: ${old_witness_one}#0" \
    "$lifecycle_transcript"
  grep -Fqx "STALE_PREDECESSOR_REJECTED_OK" "$lifecycle_transcript"
  grep -Fqx \
    "user error (the selected board output is not a current record for this witness)" \
    "$lifecycle_transcript"
  grep -Fqx \
    "state ACTIVE seq 1 native 1 keys 2-of-5 witnesses 3 (toad 2) bond intact tx ccf10efe3b90833374cf712fdbe2b246f88aadf34c170c9074d16754cdf5c6f2#0 watchable 3/3" \
    "$lifecycle_transcript"
  grep -Fqx \
    "refunded: 4 tADA to addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d" \
    "$lifecycle_transcript"
  test "$(grep -c '^board records: 2$' "$lifecycle_transcript")" -eq 1
  test "$(grep -c '^board records: 3$' "$lifecycle_transcript")" -eq 2

  for final_txid in "$update_txid" "$restore_txid"; do
    grep -Fq "$final_txid#0" "$deploy_transcript"
  done
  test "$(grep -c ' verified https .* deposit 4000000$' "$deploy_transcript")" -eq 3

  if [[ -n "${CKERI_BIN:-}" ]]; then
    final_board="$(
      "$CKERI_BIN" board list --board-manifest "$manifest"
    )"
    grep -Fqx "board records: 3" <<<"$final_board"
    grep -Fq "$update_txid#0 deposit 4000000" <<<"$final_board"
    grep -Fq "$restore_txid#0 deposit 4000000" <<<"$final_board"
    final_status="$(
      "$CKERI_BIN" status \
        --aid EBLf6spqM8kXCvklb99ObwQUuDzNDOMEne_GFypp52vi \
        --manifest deploy/preprod/m1-manifest.json \
        --board-manifest "$manifest"
    )"
    grep -Eq \
      '^source https://preprod[.]koios[.]rest/api/v1 as_of_slot [0-9]+ tip_lag_slots [0-9]+ aid EBLf6spqM8kXCvklb99ObwQUuDzNDOMEne_GFypp52vi state ACTIVE seq 1 native 1 keys 2-of-5 witnesses 3 [(]toad 2[)] tx ccf10efe3b90833374cf712fdbe2b246f88aadf34c170c9074d16754cdf5c6f2#0 watchable 3/3$' \
      <<<"$final_status"

    koios_curl_args=(--fail --silent --show-error)
    if [[ -n "${KOIOS_TOKEN:-}" ]]; then
      koios_curl_args+=(--header "Authorization: Bearer $KOIOS_TOKEN")
    fi
    all_txids=(
      "$reference_txid"
      "${post_txids[@]}"
      "$update_txid"
      "$retire_txid"
      "$restore_txid"
    )
    tx_payload="$(
      printf '%s\n' "${all_txids[@]}" |
        jq -Rsc '{_tx_hashes: split("\n") | map(select(length > 0))}'
    )"
    tx_info="$(
      curl \
        "${koios_curl_args[@]}" \
        --request POST \
        https://preprod.koios.rest/api/v1/tx_info \
        --header 'Content-Type: application/json' \
        --data "$tx_payload"
    )"
    jq -e '
      length == 7
      and all(.[];
        (.tx_hash | test("^[0-9a-f]{64}$"))
        and (.block_hash | test("^[0-9a-f]{64}$"))
        and (.block_height | type == "number")
      )
    ' <<<"$tx_info" >/dev/null

    lifecycle_utxos="$(
      curl \
        "${koios_curl_args[@]}" \
        --request POST \
        https://preprod.koios.rest/api/v1/tx_utxos \
        --header 'Content-Type: application/json' \
        --data "$(
          jq -cn \
            --arg update "$update_txid" \
            --arg retire "$retire_txid" \
            '{_tx_hashes: [$update, $retire]}'
        )"
    )"
    jq -e \
      --arg update "$update_txid" \
      --arg old "$old_witness_one" \
      --arg retire "$retire_txid" \
      --arg retired "$old_witness_three" \
      --arg policy "$policy" \
      --arg board "$board_address" \
      --arg refund \
        "addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d" '
        length == 2
        and any(.[]; .tx_hash == $update
          and any(.inputs[];
            .tx_hash == $old and .tx_index == 0
            and (.value | tonumber) == 4000000
            and any(.asset_list[];
              .policy_id == $policy and .quantity == "1"
            )
          )
          and any(.outputs[];
            .payment_addr.bech32 == $board
            and (.value | tonumber) == 4000000
            and any(.asset_list[];
              .policy_id == $policy and .quantity == "1"
            )
          )
        )
        and any(.[]; .tx_hash == $retire
          and any(.inputs[];
            .tx_hash == $retired and .tx_index == 0
            and (.value | tonumber) == 4000000
            and any(.asset_list[];
              .policy_id == $policy and .quantity == "1"
            )
          )
          and any(.outputs[];
            .payment_addr.bech32 == $refund
            and (.value | tonumber) == 4000000
            and (.asset_list | length) == 0
          )
          and all(.outputs[];
            all(.asset_list[]; .policy_id != $policy)
          )
        )
      ' <<<"$lifecycle_utxos" >/dev/null

    dial="$(
      curl \
        --fail \
        --silent \
        --show-error \
        --output /dev/null \
        --write-out '%{http_code}:%{size_download}' \
        https://witness-1.preprod.plutimus.com/oobi/BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI/controller
    )"
    test "$dial" = "200:1239"

    echo "M1 board transcripts, vertical journey, lifecycle, refund, and seven transactions are live: OK"
  else
    echo "M1 captured board transcripts and lifecycle are internally consistent: OK"
  fi
)

check_historical_board_base_assertions
