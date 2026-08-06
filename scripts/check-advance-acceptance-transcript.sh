#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

transcript="${1:-deploy/preprod/m1-advance-acceptance.txt}"
register_transcript="${2:-deploy/preprod/m1-register-acceptance.txt}"
historical_negative="${3:-deploy/preprod/m1-advance-historical-negative-acceptance.txt}"

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

# The 1-of-1 primary capture used --validator-test-under-signed solely as an
# immutable-M1 compatibility override and settled; it is not negative proof.
# Require the separate accepted 2-of-5/three-witness capture where each named
# validator control actually reached script evaluation and failed.
if grep -q $'\r' "$historical_negative" || grep -q $'\033' "$historical_negative"; then
  echo "historical advance negative capture must be plain text" >&2
  exit 1
fi
historical_aid="$(sed -n 's/^Identifier:[[:space:]]*//p' "$historical_negative" | sort -u)"
[[ "$historical_aid" =~ ^E[A-Za-z0-9_-]{43}$ ]]
grep -Eq '^state ACTIVE seq 0 native 0 keys 2-of-5 witnesses 3 [(]toad 2[)] bond intact tx [0-9a-f]{64}#0$' \
  "$historical_negative"
grep -Eq '^state ACTIVE seq 1 native 1 keys 2-of-5 witnesses 3 [(]toad 2[)] bond intact tx [0-9a-f]{64}#0$' \
  "$historical_negative"
grep -Fqx 'signature count: 5' "$historical_negative"

require_validator_failure_after() {
  local flag="$1"
  local warning="$2"
  local control_line warning_line failure_line
  control_line="$(grep -n -- "$flag$" "$historical_negative" | tail -1 | cut -d: -f1)"
  warning_line="$(grep -nF "$warning" "$historical_negative" | tail -1 | cut -d: -f1)"
  failure_line="$(awk -v start="$control_line" \
    'NR > start && /Error: The following scripts have execution failures:/ { print NR; exit }' \
    "$historical_negative")"
  test -n "$failure_line"
  test "$control_line" -lt "$warning_line"
  test "$warning_line" -lt "$failure_line"
}

require_validator_failure_after \
  '--validator-test-under-signed' \
  'warning: ACCEPTANCE-ONLY under-signed package will be sent to real validator evaluation'
require_validator_failure_after \
  '--validator-test-under-witnessed' \
  'warning: ACCEPTANCE-ONLY under-witnessed package will be sent to real validator evaluation'
require_validator_failure_after \
  '--validator-test-stale' \
  'warning: ACCEPTANCE-ONLY stale replay package will be sent to real validator evaluation'

if [[ -n "${CKERI_BIN:-}" ]]; then
  payload="$(jq -cn --arg tx "$advance_txid" '{_tx_hashes: [$tx]}')"
  curl_args=(--fail --silent --show-error)
  if [[ -n "${KOIOS_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: Bearer $KOIOS_TOKEN")
  fi
  tx_info="$(curl "${curl_args[@]}" --request POST \
    https://preprod.koios.rest/api/v1/tx_info \
    --header 'Content-Type: application/json' --data "$payload")"
  jq -e 'length == 1 and .[0].block_hash != null' <<<"$tx_info" >/dev/null
  echo "M1 in-process advance is live; 2-of-5 under-signed, under-witnessed, and stale controls fail: OK"
else
  echo "M1 advance happy-path and independent 2-of-5 validator negatives are internally consistent: OK"
fi
