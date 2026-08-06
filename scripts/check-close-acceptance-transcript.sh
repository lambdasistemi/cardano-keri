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
