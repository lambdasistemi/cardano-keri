#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

transcript="${1:-deploy/preprod/m1-close-acceptance.txt}"
advance_transcript="${2:-deploy/preprod/m1-advance-acceptance.txt}"
historical_negative="${3:-deploy/preprod/m1-close-historical-negative-acceptance.txt}"
refund_address='addr_test1qzdqjmt98smx8my6f5uum0szghuy8ff2hep2e64a9w2pehty436vwj3d2cslvu2a4aypkrqa4d6ujvldn8l6utg5yyqs4pqv6d'

if grep -q $'\r' "$transcript" || grep -q $'\033' "$transcript"; then
  echo "close transcript must be plain captured text" >&2
  exit 1
fi
test "$(wc -c <"$transcript")" -lt 30000
grep -Fqx 'ckeri 0.4.0' "$transcript"
if grep -Fq 'cardano-cli' "$transcript"; then
  echo "close transcript still invokes cardano-cli" >&2
  exit 1
fi

aid="$(sed -n 's/.* aid \(E[A-Za-z0-9_-]\{43\}\) state ACTIVE.*/\1/p' "$transcript" | sort -u)"
[[ "$aid" =~ ^E[A-Za-z0-9_-]{43}$ ]]
advance_txid="$(sed -n 's/^advance txid: \([0-9a-f]\{64\}\)$/\1/p' "$advance_transcript")"
close_txid="$(sed -n 's/^close txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript")"
[[ "$advance_txid" =~ ^[0-9a-f]{64}$ ]]
[[ "$close_txid" =~ ^[0-9a-f]{64}$ ]]
test "$advance_txid" != "$close_txid"

grep -Fq "spent checkpoint: $advance_txid#0" "$transcript"
grep -Fqx "refund: 1007 tADA to $refund_address" "$transcript"
grep -Fqx "refunded: 1007 tADA to $refund_address" "$transcript"
grep -Fqx 'signature count: 1' "$transcript"
preimage="$(sed -n 's/^preimage sha256: \([0-9a-f]\{64\}\)$/\1/p' "$transcript" | sort -u)"
[[ "$preimage" =~ ^[0-9a-f]{64}$ ]]
test "$(grep -c "^preimage sha256: $preimage$" "$transcript")" -eq 2
grep -Eq \
  "^source https://preprod[.]koios[.]rest/api/v1 as_of_slot [0-9]+ tip_lag_slots [0-9]+ aid $aid state ACTIVE seq 1 native 1 keys 1-of-1 witnesses 0 [(]toad 0[)] tx $advance_txid#0 watchable 0/0$" \
  "$transcript"
grep -Fqx \
  "source koios as_of_slot unknown tip_lag_slots unknown aid $aid state NOT REGISTERED watchable 0/0" \
  "$transcript"

active_line="$(grep -nF "tx $advance_txid#0 watchable 0/0" "$transcript" | cut -d: -f1)"
prepare_line="$(grep -nF "spent checkpoint: $advance_txid#0" "$transcript" | cut -d: -f1)"
close_line="$(grep -nF "close txid: $close_txid" "$transcript" | cut -d: -f1)"
closed_line="$(grep -nF 'state NOT REGISTERED watchable 0/0' "$transcript" | cut -d: -f1)"
test "$active_line" -lt "$prepare_line"
test "$prepare_line" -lt "$close_line"
test "$close_line" -lt "$closed_line"

if grep -q $'\r' "$historical_negative" || grep -q $'\033' "$historical_negative"; then
  echo "historical close negative capture must be plain text" >&2
  exit 1
fi
grep -Eq '^[$] docker run .*--validator-test-non-controller$' "$historical_negative"
grep -Fqx \
  'warning: ACCEPTANCE-ONLY non-controller close package will be sent to real validator evaluation' \
  "$historical_negative"
outsider_line="$(grep -n -- '--validator-test-non-controller$' "$historical_negative" | tail -1 | cut -d: -f1)"
failure_line="$(awk -v start="$outsider_line" \
  'NR > start && /Error: The following scripts have execution failures:/ { print NR; exit }' \
  "$historical_negative")"
controller_line="$(grep -n -- 'controller-signatures[.]cesr$' "$historical_negative" | tail -1 | cut -d: -f1)"
test -n "$failure_line"
test "$outsider_line" -lt "$failure_line"
test "$failure_line" -lt "$controller_line"

if [[ -n "${CKERI_BIN:-}" ]]; then
  payload="$(jq -cn --arg tx "$close_txid" '{_tx_hashes: [$tx]}')"
  curl_args=(--fail --silent --show-error)
  if [[ -n "${KOIOS_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: Bearer $KOIOS_TOKEN")
  fi
  tx_info="$(curl "${curl_args[@]}" --request POST \
    https://preprod.koios.rest/api/v1/tx_info \
    --header 'Content-Type: application/json' --data "$payload")"
  jq -e 'length == 1 and .[0].block_hash != null' <<<"$tx_info" >/dev/null
  echo "M1 in-process close/refund is live and the independent non-controller control fails: OK"
else
  echo "M1 close happy-path and independent non-controller negative are internally consistent: OK"
fi

# Preserve the complete base assertion set against its own accepted capture
# and signing package; the regenerated primary close remains checked above.
check_historical_close_base_assertions() (
  transcript=deploy/preprod/m1-close-historical-negative-acceptance.txt
  package_dir=deploy/preprod/m1-close-package
  manifest=deploy/preprod/m1-manifest.json
  if test "$(tr -d '\000' <"$transcript" | wc -c)" -ne \
    "$(wc -c <"$transcript")" ||
    grep -q $'\r' "$transcript" ||
    grep -q $'\033' "$transcript"; then
    echo "close transcript must be plain captured text" >&2
    exit 1
  fi

  test "$(wc -c <"$transcript")" -lt 20000
  grep -Fqx "Library version: 1.3.5" "$transcript"
  grep -Fqx "ckeri 0.0.0" "$transcript"
  test "$(grep -c '^\$ ' "$transcript")" -eq 24

  mapfile -t identifiers < <(
    sed -n 's/^Identifier:[[:space:]]*//p' "$transcript" | sort -u
  )
  test "${#identifiers[@]}" -eq 1
  aid="${identifiers[0]}"
  [[ "$aid" =~ ^E[A-Za-z0-9_-]{43}$ ]]
  grep -Fqx "Prefix  $aid" "$transcript"
  test "$(grep -c '^Prefix  E[A-Za-z0-9_-]\{43\}$' "$transcript")" -eq 2

  test "$(
    grep -Ec \
      '^[$] docker run .* incept .*--icount 1 --isith 1 --ncount 1 --nsith 1 --toad 0$' \
      "$transcript"
  )" -eq 2
  grep -Fqx "state NOT REGISTERED aid $aid" "$transcript"

  mapfile -t premint_txids < <(
    sed -n 's/^.*premint txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript"
  )
  mapfile -t register_txids < <(
    sed -n 's/^register txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript"
  )
  mapfile -t close_txids < <(
    sed -n 's/^close txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript"
  )
  test "${#premint_txids[@]}" -eq 1
  test "${#register_txids[@]}" -eq 1
  test "${#close_txids[@]}" -eq 1
  test "$(
    printf '%s\n' \
      "${premint_txids[0]}" \
      "${register_txids[0]}" \
      "${close_txids[0]}" |
      sort -u |
      wc -l
  )" -eq 3

  register_txid="${register_txids[0]}"
  close_txid="${close_txids[0]}"
  active_status="state ACTIVE seq 0 native 0 keys 1-of-1 witnesses 0 (toad 0) bond intact tx ${register_txid}#0"
  closed_status="state NOT REGISTERED (closed at ${close_txid}) aid ${aid}"
  grep -Fqx "$active_status" "$transcript"
  grep -Fqx "$closed_status" "$transcript"
  grep -Fqx "escrow: 1007 tADA (min 2 + D 1000 + B 5)" "$transcript"
  grep -Fqx "spent checkpoint: ${register_txid}#0" "$transcript"

  refund_address="$(jq -r .refundAddress "$package_dir/package.json")"
  refund_lovelace="$(jq -r .refundLovelace "$package_dir/package.json")"
  test "$refund_lovelace" -eq 1007000000
  grep -Fqx "refund: 1007 tADA to $refund_address" "$transcript"
  grep -Fqx "refunded: 1007 tADA to $refund_address" "$transcript"

  test "$(
    grep -Ec '^[$] .*[/]ckeri close .*--signing-package ' "$transcript"
  )" -eq 1
  test "$(
    grep -Ec '^[$] sudo env .*[/]ckeri close .*--validator-test-non-controller$' \
      "$transcript"
  )" -eq 1
  test "$(
    grep -Ec '^[$] sudo env .*[/]ckeri close .*controller-signatures.cesr$' \
      "$transcript"
  )" -eq 1
  grep -Fqx \
    "warning: ACCEPTANCE-ONLY non-controller close package will be sent to real validator evaluation" \
    "$transcript"
  grep -Fq "Error: The following scripts have execution failures:" "$transcript"
  grep -Fq \
    "Script hash: 581c0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734" \
    "$transcript"
  grep -Fq \
    "ScriptInfo: SpendingScript (TxOutRef {txOutRefId = $register_txid, txOutRefIdx = 0})" \
    "$transcript"
  grep -Fq "Script language: PlutusV3" "$transcript"
  grep -Fq "Protocol version: Version 11" "$transcript"
  grep -Fq "Caused by: (error)" "$transcript"
  if grep -Fq "Script base64 encoded" "$transcript"; then
    echo "validator evidence must not contain opaque base64 dumps" >&2
    exit 1
  fi

  active_line="$(grep -nF "$active_status" "$transcript" | cut -d: -f1)"
  prepare_line="$(
    grep -nE '^[$] .*[/]ckeri close .*--signing-package ' "$transcript" |
      cut -d: -f1
  )"
  negative_line="$(
    grep -nE '^[$] sudo env .*[/]ckeri close .*--validator-test-non-controller$' \
      "$transcript" |
      cut -d: -f1
  )"
  close_line="$(grep -nF "close txid: $close_txid" "$transcript" | cut -d: -f1)"
  closed_line="$(grep -nF "$closed_status" "$transcript" | cut -d: -f1)"
  test "$active_line" -lt "$prepare_line"
  test "$prepare_line" -lt "$negative_line"
  test "$negative_line" -lt "$close_line"
  test "$close_line" -lt "$closed_line"

  test "$(jq -r .schema "$package_dir/package.json")" = \
    "cardano-keri/close-signing-package/v1"
  test "$(jq -r .aid "$package_dir/package.json")" = "$aid"
  test "$(jq -r .spentReference "$package_dir/package.json")" = \
    "${register_txid}#0"
  test "$(jq -r .preimageFile "$package_dir/package.json")" = \
    "close-message.cbor"
  preimage_hash="$(
    sha256sum "$package_dir/close-message.cbor" | cut -d' ' -f1
  )"
  test "$(jq -r .preimageSha256 "$package_dir/package.json")" = \
    "$preimage_hash"
  test "$(grep -c "^preimage sha256: $preimage_hash$" "$transcript")" -eq 3
  for signature_file in \
    "$package_dir/controller-signatures.cesr" \
    "$package_dir/outsider-signatures.cesr"; do
    test "$(wc -l <"$signature_file")" -eq 1
    awk 'length != 88 { exit 1 }' "$signature_file"
  done
  if cmp -s \
    "$package_dir/controller-signatures.cesr" \
    "$package_dir/outsider-signatures.cesr"; then
    echo "controller and outsider signatures must differ" >&2
    exit 1
  fi

  grep -Fqx \
    '$ docker volume rm ckeri-161-controller-final-20260729' \
    "$transcript"
  grep -Fqx \
    '$ docker volume rm ckeri-161-outsider-final-20260729' \
    "$transcript"

  if [[ -n "${CKERI_BIN:-}" ]]; then
    actual_status="$("$CKERI_BIN" status --aid "$aid" --manifest "$manifest")"
    test "$actual_status" = \
      "source koios as_of_slot unknown tip_lag_slots unknown aid $aid state NOT REGISTERED watchable 0/0"

    curl_args=(
      --fail
      --silent
      --show-error
    )
    if [[ -n "${KOIOS_TOKEN:-}" ]]; then
      curl_args+=(--header "Authorization: Bearer $KOIOS_TOKEN")
    fi

    tx_payload="$(
      printf '%s\n' \
        "${premint_txids[0]}" \
        "$register_txid" \
        "$close_txid" |
        jq -Rsc '{_tx_hashes: split("\n") | map(select(length > 0))}'
    )"
    tx_info="$(
      curl \
        "${curl_args[@]}" \
        --request POST \
        https://preprod.koios.rest/api/v1/tx_info \
        --header 'Content-Type: application/json' \
        --data "$tx_payload"
    )"
    jq -e '
      length == 3
      and all(.[];
        (.tx_hash | test("^[0-9a-f]{64}$"))
        and (.block_hash | test("^[0-9a-f]{64}$"))
        and (.block_height | type == "number")
      )
    ' <<<"$tx_info" >/dev/null

    close_utxos="$(
      curl \
        "${curl_args[@]}" \
        --request POST \
        https://preprod.koios.rest/api/v1/tx_utxos \
        --header 'Content-Type: application/json' \
        --data "$(jq -cn --arg tx "$close_txid" '{_tx_hashes: [$tx]}')"
    )"
    policy="$(jq -r .checkpoint.policyId "$manifest")"
    jq -e \
      --arg close "$close_txid" \
      --arg register "$register_txid" \
      --arg policy "$policy" \
      --arg refund "$refund_address" \
      --argjson lovelace "$refund_lovelace" '
        length == 1
        and .[0].tx_hash == $close
        and any(.[0].inputs[];
          .tx_hash == $register
          and .tx_index == 0
          and (.value | tonumber) == $lovelace
          and (.asset_list | length) == 1
          and .asset_list[0].policy_id == $policy
          and .asset_list[0].quantity == "1"
        )
        and ([.[0].outputs[] |
          select(
            .payment_addr.bech32 == $refund
            and (.value | tonumber) == $lovelace
            and (.asset_list | length) == 0
          )
        ] | length) == 1
        and all(.[0].outputs[];
          all(.asset_list[]; .policy_id != $policy)
        )
      ' <<<"$close_utxos" >/dev/null

    asset_name="$(
      jq -r \
        --arg register "$register_txid" \
        --arg policy "$policy" '
          .[0].inputs[]
          | select(.tx_hash == $register and .tx_index == 0)
          | .asset_list[]
          | select(.policy_id == $policy and .quantity == "1")
          | .asset_name
        ' <<<"$close_utxos"
    )"
    [[ "$asset_name" =~ ^[0-9a-f]{64}$ ]]
    history="$(
      curl \
        "${curl_args[@]}" \
        "https://preprod.koios.rest/api/v1/asset_history?_asset_policy=${policy}&_asset_name=${asset_name}"
    )"
    jq -e \
      --arg close "$close_txid" '
        length == 1
        and (.[0].minting_txs | max_by(.block_time)).tx_hash == $close
        and (.[0].minting_txs | max_by(.block_time)).quantity == "-1"
      ' <<<"$history" >/dev/null

    redeemers="$(
      curl \
        "${curl_args[@]}" \
        "https://preprod.koios.rest/api/v1/script_redeemers?_script_hash=${policy}"
    )"
    jq -e \
      --arg close "$close_txid" '
        length == 1
        and any(.[0].redeemers[];
          .tx_hash == $close and .purpose == "mint"
        )
        and any(.[0].redeemers[];
          .tx_hash == $close and .purpose == "spend"
        )
      ' <<<"$redeemers" >/dev/null

    echo "M1 close transcript, package, validator negative, refund, and three settled transactions are live: OK"
  else
    echo "M1 captured close transcript and package are internally consistent: OK"
  fi
)

check_historical_close_base_assertions
