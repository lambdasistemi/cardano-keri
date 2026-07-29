#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

transcript="${1:-deploy/preprod/m1-advance-acceptance.txt}"
package_dir="${2:-deploy/preprod/m1-advance-package}"
manifest="${3:-deploy/preprod/m1-manifest.json}"

if grep -q $'\r' "$transcript" || grep -q $'\033' "$transcript"; then
  echo "advance transcript must be plain captured text" >&2
  exit 1
fi

test "$(wc -c <"$transcript")" -lt 50000
grep -Fqx "Library version: 1.3.5" "$transcript"
grep -Fqx "ckeri 0.0.0 " "$transcript"
test "$(grep -c '^\$ ' "$transcript")" -eq 34

mapfile -t identifiers < <(
  sed -n 's/^Identifier:[[:space:]]*//p' "$transcript" | sort -u
)
test "${#identifiers[@]}" -eq 1
aid="${identifiers[0]}"
[[ "$aid" =~ ^E[A-Za-z0-9_-]{43}$ ]]

grep -Eq \
  '^[$] docker run .* incept .*--icount 5 --isith 2 --ncount 5 --nsith 2 .*--toad 2 --receipt-endpoint$' \
  "$transcript"
grep -Eq \
  '^[$] docker run .* rotate .*--next-count 5 --isith 2 --nsith 2 --toad 2 --receipt-endpoint$' \
  "$transcript"
test "$(grep -c '/controller resolved$' "$transcript")" -eq 3
test "$(grep -c '^Receipts:[[:space:]]*3$' "$transcript")" -eq 4
test "$(grep -c '^Threshold:[[:space:]]*2$' "$transcript")" -eq 4

mapfile -t premint_txids < <(
  sed -n 's/^premint txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript"
)
mapfile -t register_txids < <(
  sed -n 's/^register txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript"
)
mapfile -t observer_txids < <(
  sed -n 's/^observer registration txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript"
)
mapfile -t advance_txids < <(
  sed -n 's/^advance txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript"
)
test "${#premint_txids[@]}" -eq 1
test "${#register_txids[@]}" -eq 1
test "${#observer_txids[@]}" -eq 1
test "${#advance_txids[@]}" -eq 1
test "$(
  printf '%s\n' \
    "${premint_txids[@]}" \
    "${register_txids[@]}" \
    "${observer_txids[@]}" \
    "${advance_txids[@]}" |
    sort -u |
    wc -l
)" -eq 4

register_txid="${register_txids[0]}"
advance_txid="${advance_txids[0]}"
seq_zero="state ACTIVE seq 0 native 0 keys 2-of-5 witnesses 3 (toad 2) bond intact tx ${register_txid}#0"
seq_one="state ACTIVE seq 1 native 1 keys 2-of-5 witnesses 3 (toad 2) bond intact tx ${advance_txid}#0"
grep -Fqx "$seq_zero" "$transcript"
grep -Fqx "$seq_one" "$transcript"

grep -Eq '^[$] .*ckeri advance .*--signing-package ' "$transcript"
test "$(grep -Ec '^[$] .*ckeri advance .*--validator-test-under-signed$' "$transcript")" -eq 2
test "$(grep -Ec '^[$] .*ckeri advance .*--validator-test-under-witnessed$' "$transcript")" -eq 2
test "$(grep -Ec '^[$] .*ckeri advance .*--validator-test-stale$' "$transcript")" -eq 1
grep -Fqx \
  "warning: ACCEPTANCE-ONLY stale replay package will be sent to real validator evaluation" \
  "$transcript"
test "$(
  grep -c \
    'ScriptInfo: RewardingScript (ScriptCredential 50dbbef1c38646d29a1e333337fc5244fe2da3149bf9d5545e5b92c6)' \
    "$transcript"
)" -ge 5
grep -Fq "ConwayWithdrawalsMissingAccounts" "$transcript"
grep -Fq "PermissionError: [Errno 13] Permission denied" "$transcript"
if grep -Fq "Script base64 encoded" "$transcript"; then
  echo "validator evidence must not contain opaque base64 dumps" >&2
  exit 1
fi

seq_zero_line="$(grep -nF "$seq_zero" "$transcript" | head -1 | cut -d: -f1)"
rotate_line="$(grep -nE '^[$] docker run .* rotate ' "$transcript" | head -1 | cut -d: -f1)"
under_signed_line="$(
  grep -nE '^[$] .*--validator-test-under-signed$' "$transcript" |
    head -1 |
    cut -d: -f1
)"
advance_line="$(grep -nF "advance txid: $advance_txid" "$transcript" | cut -d: -f1)"
seq_one_line="$(grep -nF "$seq_one" "$transcript" | cut -d: -f1)"
stale_line="$(
  grep -nE '^[$] .*--validator-test-stale$' "$transcript" |
    cut -d: -f1
)"
test "$seq_zero_line" -lt "$rotate_line"
test "$rotate_line" -lt "$under_signed_line"
test "$under_signed_line" -lt "$advance_line"
test "$advance_line" -lt "$seq_one_line"
test "$seq_one_line" -lt "$stale_line"

test "$(jq -r .schema "$package_dir/package.json")" = \
  "cardano-keri/advance-signing-package/v1"
test "$(jq -r .aid "$package_dir/package.json")" = "$aid"
test "$(jq -r .spentReference "$package_dir/package.json")" = \
  "${register_txid}#0"
preimage_hash="$(
  sha256sum "$package_dir/advance-message.cbor" | cut -d' ' -f1
)"
test "$(jq -r .preimageSha256 "$package_dir/package.json")" = \
  "$preimage_hash"
test "$(grep -c "^preimage sha256: $preimage_hash$" "$transcript")" -eq 3
test "$(wc -l <"$package_dir/controller-signatures.cesr")" -eq 5
awk 'length != 88 { exit 1 }' "$package_dir/controller-signatures.cesr"

if [[ -n "${CKERI_BIN:-}" ]]; then
  actual_status="$(
    "$CKERI_BIN" status "$aid" \
      --manifest "$manifest" \
      --board-manifest deploy/preprod/board-manifest.json
  )"
  test "$actual_status" = "$seq_one watchable 3/3"

  tx_payload="$(
    printf '%s\n' \
      "${premint_txids[@]}" \
      "${register_txids[@]}" \
      "${observer_txids[@]}" \
      "${advance_txids[@]}" |
      jq -Rsc '{_tx_hashes: split("\n") | map(select(length > 0))}'
  )"
  curl_args=(
    --fail
    --silent
    --show-error
    --request POST
    https://preprod.koios.rest/api/v1/tx_info
    --header 'Content-Type: application/json'
    --data "$tx_payload"
  )
  if [[ -n "${KOIOS_TOKEN:-}" ]]; then
    curl_args+=(--header "Authorization: Bearer $KOIOS_TOKEN")
  fi
  tx_info="$(curl "${curl_args[@]}")"
  jq -e '
    length == 4
    and all(.[];
      (.tx_hash | test("^[0-9a-f]{64}$"))
      and (.block_hash | test("^[0-9a-f]{64}$"))
      and (.block_height | type == "number")
    )
  ' <<<"$tx_info" >/dev/null

  echo "M1 advance transcript, package, and four settled transactions are live: OK"
else
  echo "M1 captured advance transcript and package are internally consistent: OK"
fi
