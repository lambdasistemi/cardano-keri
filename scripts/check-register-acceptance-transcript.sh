#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

transcript="${1:-deploy/preprod/m1-register-acceptance.txt}"
historical_negative="${2:-deploy/preprod/m1-register-historical-negative-acceptance.txt}"

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

# The current live capture above proves the in-process happy path and funding
# failure. These accepted M1 captures independently preserve the three
# registration fail-closed controls that must not be weakened when the primary
# journey is refreshed.
if grep -q $'\r' "$historical_negative" || grep -q $'\033' "$historical_negative"; then
  echo "historical registration negative capture must be plain text" >&2
  exit 1
fi
grep -Fqx \
  'user error (checkpoint already registered; refusing before premint)' \
  "$historical_negative"
grep -Fqx \
  'user error (checkpoint lookup is ambiguous: 2 live outputs)' \
  "$historical_negative"
grep -Fqx \
  'user error (declared witnesses have no board record check yet; pass --allow-unlisted-witnesses to acknowledge reduced watchability)' \
  "$historical_negative"
grep -Eq '^state ACTIVE seq 0 native 0 keys 2-of-5 witnesses 3 [(]toad 2[)] bond intact tx [0-9a-f]{64}#0$' \
  "$historical_negative"

already_line="$(grep -nF 'checkpoint already registered; refusing before premint' "$historical_negative" | cut -d: -f1)"
ambiguous_line="$(grep -nF 'checkpoint lookup is ambiguous: 2 live outputs' "$historical_negative" | cut -d: -f1)"
unlisted_line="$(grep -nF 'declared witnesses have no board record check yet' "$historical_negative" | cut -d: -f1)"
test "$already_line" -lt "$ambiguous_line"
test "$ambiguous_line" -lt "$unlisted_line"

if [[ -n "${CKERI_BIN:-}" ]]; then
  payload="$(jq -cn --arg a "$premint_txid" --arg b "$register_txid" '{_tx_hashes: [$a, $b]}')"
  curl_args=(--fail --silent --show-error)
  if [[ -n "${KOIOS_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: Bearer $KOIOS_TOKEN")
  fi
  tx_info="$(curl "${curl_args[@]}" --request POST \
    https://preprod.koios.rest/api/v1/tx_info \
    --header 'Content-Type: application/json' --data "$payload")"
  jq -e 'length == 2 and all(.[]; .block_hash != null)' <<<"$tx_info" >/dev/null
  echo "M1 in-process registration is live; funding and historical registration controls are fail-closed: OK"
else
  echo "M1 registration happy-path and independent historical negatives are internally consistent: OK"
fi
