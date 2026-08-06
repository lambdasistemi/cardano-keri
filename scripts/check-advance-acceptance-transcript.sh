#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

transcript="${1:-deploy/preprod/m1-advance-acceptance.txt}"
register_transcript="${2:-deploy/preprod/m1-register-acceptance.txt}"

if grep -q $'\r' "$transcript" || grep -q $'\033' "$transcript"; then
  echo "advance transcript must be plain captured text" >&2
  exit 1
fi
test "$(wc -c <"$transcript")" -lt 30000
grep -Fqx 'ckeri 0.4.0' "$transcript"
if grep -Fq 'cardano-cli' "$transcript"; then
  echo "advance transcript still invokes cardano-cli" >&2
  exit 1
fi

aid="$(sed -n 's/^Identifier:[[:space:]]*//p' "$transcript" | sort -u)"
[[ "$aid" =~ ^E[A-Za-z0-9_-]{43}$ ]]
grep -Fq "Identifier: $aid" "$register_transcript"
register_txid="$(sed -n 's/^register txid: \([0-9a-f]\{64\}\)$/\1/p' "$register_transcript")"
advance_txid="$(sed -n 's/^advance txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript")"
[[ "$register_txid" =~ ^[0-9a-f]{64}$ ]]
[[ "$advance_txid" =~ ^[0-9a-f]{64}$ ]]
test "$register_txid" != "$advance_txid"

grep -Eq '^[$] docker run .* rotate .*--next-count 1 .*--isith 1 .*--nsith 1 .*--toad 0$' "$transcript"
grep -Eq '^[$] .*ckeri advance .*--signing-package ' "$transcript"
grep -Eq '^[$] .*ckeri advance .*--controller-signatures .*--validator-test-under-signed$' "$transcript"
grep -Fqx 'warning: ACCEPTANCE-ONLY under-signed package will be sent to real validator evaluation' "$transcript"
grep -Fqx 'signature count: 1' "$transcript"
preimage="$(sed -n 's/^preimage sha256: \([0-9a-f]\{64\}\)$/\1/p' "$transcript" | sort -u)"
[[ "$preimage" =~ ^[0-9a-f]{64}$ ]]
test "$(grep -c "^preimage sha256: $preimage$" "$transcript")" -eq 2
grep -Eq \
  "^source https://preprod[.]koios[.]rest/api/v1 as_of_slot [0-9]+ tip_lag_slots [0-9]+ aid $aid state ACTIVE seq 0 native 0 keys 1-of-1 witnesses 0 [(]toad 0[)] tx $register_txid#0 watchable 0/0$" \
  "$transcript"
grep -Eq \
  "^source https://preprod[.]koios[.]rest/api/v1 as_of_slot [0-9]+ tip_lag_slots [0-9]+ aid $aid state ACTIVE seq 1 native 1 keys 1-of-1 witnesses 0 [(]toad 0[)] tx $advance_txid#0 watchable 0/0$" \
  "$transcript"

old_line="$(grep -nF "tx $register_txid#0 watchable 0/0" "$transcript" | cut -d: -f1)"
rotate_line="$(grep -nE '^[$] docker run .* rotate ' "$transcript" | cut -d: -f1)"
advance_line="$(grep -nF "advance txid: $advance_txid" "$transcript" | cut -d: -f1)"
new_line="$(grep -nF "tx $advance_txid#0 watchable 0/0" "$transcript" | cut -d: -f1)"
test "$old_line" -lt "$rotate_line"
test "$rotate_line" -lt "$advance_line"
test "$advance_line" -lt "$new_line"

if [[ -n "${CKERI_BIN:-}" ]]; then
  payload="$(jq -cn --arg tx "$advance_txid" '{_tx_hashes: [$tx]}')"
  tx_info="$(curl --fail --silent --show-error --request POST \
    https://preprod.koios.rest/api/v1/tx_info \
    --header 'Content-Type: application/json' --data "$payload")"
  jq -e 'length == 1 and .[0].block_hash != null' <<<"$tx_info" >/dev/null
  echo "M1 in-process advance transaction is live: OK"
else
  echo "M1 in-process advance transcript is internally consistent: OK"
fi
