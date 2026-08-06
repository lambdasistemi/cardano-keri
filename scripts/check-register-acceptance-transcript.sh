#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

transcript="${1:-deploy/preprod/m1-register-acceptance.txt}"

if grep -q $'\r' "$transcript" || grep -q $'\033' "$transcript"; then
  echo "registration transcript must be plain captured text" >&2
  exit 1
fi
test "$(wc -c <"$transcript")" -lt 30000
grep -Fqx 'ckeri 0.4.0' "$transcript"
grep -Fqx 'Library version: 1.3.5' "$transcript"
if grep -Fq 'cardano-cli' "$transcript"; then
  echo "registration transcript still invokes cardano-cli" >&2
  exit 1
fi

aid="$(sed -n 's/^Identifier:[[:space:]]*//p' "$transcript" | sort -u)"
[[ "$aid" =~ ^E[A-Za-z0-9_-]{43}$ ]]
grep -Eq \
  'RegistrationFundingSelectionFailed (EmptyIndexedSnapshot|[(]InsufficientFundingValue )' \
  "$transcript"
grep -Fqx 'exit status: 1' "$transcript"

premint_txid="$(sed -n 's/^premint txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript")"
register_txid="$(sed -n 's/^register txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript")"
[[ "$premint_txid" =~ ^[0-9a-f]{64}$ ]]
[[ "$register_txid" =~ ^[0-9a-f]{64}$ ]]
test "$premint_txid" != "$register_txid"
grep -Fqx 'escrow: 1007 tADA (min 2 + D 1000 + B 5)' "$transcript"
grep -Eq \
  "^source https://preprod[.]koios[.]rest/api/v1 as_of_slot [0-9]+ tip_lag_slots [0-9]+ aid $aid state ACTIVE seq 0 native 0 keys 1-of-1 witnesses 0 [(]toad 0[)] tx $register_txid#0 watchable 0/0$" \
  "$transcript"

underfunded_line="$(grep -n 'RegistrationFundingSelectionFailed' "$transcript" | cut -d: -f1)"
premint_line="$(grep -nF "premint txid: $premint_txid" "$transcript" | cut -d: -f1)"
register_line="$(grep -nF "register txid: $register_txid" "$transcript" | cut -d: -f1)"
status_line="$(grep -nF "tx $register_txid#0 watchable 0/0" "$transcript" | cut -d: -f1)"
test "$underfunded_line" -lt "$premint_line"
test "$premint_line" -lt "$register_line"
test "$register_line" -lt "$status_line"

if [[ -n "${CKERI_BIN:-}" ]]; then
  payload="$(jq -cn --arg a "$premint_txid" --arg b "$register_txid" '{_tx_hashes: [$a, $b]}')"
  tx_info="$(curl --fail --silent --show-error --request POST \
    https://preprod.koios.rest/api/v1/tx_info \
    --header 'Content-Type: application/json' --data "$payload")"
  jq -e 'length == 2 and all(.[]; .block_hash != null)' <<<"$tx_info" >/dev/null
  echo "M1 in-process registration and underfunded negative are live: OK"
else
  echo "M1 in-process registration transcript is internally consistent: OK"
fi
