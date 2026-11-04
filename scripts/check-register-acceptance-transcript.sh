#!/usr/bin/env bash
set -euo pipefail

# Checks the recorded history of the version 1 generation: the captured text
# and, with CKERI_BIN set, that the recorded transactions and checkpoint outputs
# are still on preprod. The version 2 `status` reader is covered by the
# end-to-end and command-line suites, not here.

cd "$(dirname "$0")/.."

# Recorded history of the version 1 generation: the recorded checkpoint output
# is checked on Koios without decoding its datum (the version 2 `status`
# reader is covered by the end-to-end and command-line suites). The token name
# is the blake2b-256 of the checkpoint domain tag, the E code and the AID digest.
koios_utxo_info() { # <tx#ix>: the Koios record of that output
  local args=(--fail --silent --show-error)
  if [[ -n "${KOIOS_TOKEN:-}" ]]; then
    args+=(--header "Authorization: Bearer $KOIOS_TOKEN")
  fi
  curl "${args[@]}" --request POST https://preprod.koios.rest/api/v1/utxo_info \
    --header 'Content-Type: application/json' \
    --data "$(jq -cn --arg ref "$1" '{_utxo_refs: [$ref], _extended: true}')"
}

checkpoint_output_held() { # <koios record> <aid> <checkpoint manifest>
  local name
  name="$(
    {
      printf 'cardano-keri/checkpoint-asset/v1\x45'
      printf 'A%s' "${2:1}" | tr '_-' '/+' | base64 -d | tail -c 32
    } | b2sum -l 256 | cut -d' ' -f1
  )"
  jq -e \
    --arg address "$(jq -r .checkpoint.address "$3")" \
    --arg policy "$(jq -r .checkpoint.policyId "$3")" \
    --arg name "$name" '
      length == 1
      and .[0].is_spent == false
      and .[0].address == $address
      and any(.[0].asset_list[]?;
        .policy_id == $policy and .asset_name == $name and .quantity == "1")
    ' <<<"$1" >/dev/null
}

# The held check above must be able to fail: a wrong output reference and a
# wrong token name are each refused.
check_checkpoint_output() { # <tx#ix> <aid> <checkpoint manifest>
  local held other wrong_aid
  held="$(koios_utxo_info "$1")"
  checkpoint_output_held "$held" "$2" "$3"
  other="$(koios_utxo_info "${1%#*}#99")"
  if checkpoint_output_held "$other" "$2" "$3"; then
    echo "refusal control failed: a wrong tx#ix was accepted" >&2
    exit 1
  fi
  wrong_aid="${2%?}$([[ "$2" == *A ]] && echo B || echo A)"
  if checkpoint_output_held "$held" "$wrong_aid" "$3"; then
    echo "refusal control failed: a wrong token name was accepted" >&2
    exit 1
  fi
}

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

# Preserve the complete base assertion set against its own accepted capture;
# the regenerated primary registration remains checked above.
check_historical_register_base_assertions() (
  transcript=deploy/preprod/m1-register-historical-negative-acceptance.txt
  manifest=deploy/preprod/m1-manifest.json
  if grep -q $'\r' "$transcript" || grep -q $'\033' "$transcript"; then
    echo "registration transcript must be plain captured text" >&2
    exit 1
  fi

  # Leave ample room for the surrounding PR narrative under GitHub's body limit.
  test "$(wc -c <"$transcript")" -lt 50000
  grep -Fqx "Library version: 1.3.5" "$transcript"
  grep -Fqx "ckeri 0.0.0" "$transcript"
  test "$(grep -c '^\$ ' "$transcript")" -eq 28

  mapfile -t identifiers < <(
    sed -n 's/^Identifier:[[:space:]]*//p' "$transcript"
  )
  test "${#identifiers[@]}" -eq 2
  single_aid="${identifiers[0]}"
  multi_aid="${identifiers[1]}"
  [[ "$single_aid" =~ ^E[A-Za-z0-9_-]{43}$ ]]
  [[ "$multi_aid" =~ ^E[A-Za-z0-9_-]{43}$ ]]
  test "$single_aid" != "$multi_aid"

  grep -Fqx "state NOT REGISTERED aid $single_aid" "$transcript"
  grep -Fqx "state NOT REGISTERED aid $multi_aid" "$transcript"
  grep -Eq \
    '^[$] docker run .* incept .*--icount 1 --isith 1 --ncount 1 --nsith 1 --toad 0$' \
    "$transcript"
  grep -Eq \
    '^[$] docker run .* incept .*--icount 5 --isith 2 --ncount 5 --nsith 2 .*--toad 2$' \
    "$transcript"
  test "$(grep -c '/controller resolved$' "$transcript")" -eq 3
  grep -Eq '^Count:[[:space:]]*3$' "$transcript"
  grep -Eq '^Receipts:[[:space:]]*3$' "$transcript"
  grep -Eq '^Threshold:[[:space:]]*2$' "$transcript"

  mapfile -t premint_txids < <(
    sed -n 's/^premint txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript"
  )
  mapfile -t register_txids < <(
    sed -n 's/^register txid: \([0-9a-f]\{64\}\)$/\1/p' "$transcript"
  )
  test "${#premint_txids[@]}" -eq 3
  test "${#register_txids[@]}" -eq 3
  test "$(printf '%s\n' "${premint_txids[@]}" "${register_txids[@]}" | sort -u | wc -l)" -eq 6

  grep -Fqx \
    "state ACTIVE seq 0 native 0 keys 1-of-1 witnesses 0 (toad 0) bond intact tx ${register_txids[0]}#0" \
    "$transcript"
  grep -Fqx \
    "state ACTIVE seq 0 native 0 keys 2-of-5 witnesses 3 (toad 2) bond intact tx ${register_txids[2]}#0" \
    "$transcript"
  test "$(grep -c '^escrow: 1007 tADA (min 2 + D 1000 + B 5)$' "$transcript")" -eq 3

  mapfile -t register_commands < <(grep '^\$ sudo env .*[/]ckeri register' "$transcript")
  test "${#register_commands[@]}" -eq 6
  for command in "${register_commands[@]}"; do
    grep -Fq 'CKERI_NETWORK=preprod' <<<"$command"
    grep -Fq 'CKERI_NETWORK_MAGIC=1' <<<"$command"
    grep -Fq 'CKERI_KEL=' <<<"$command"
    grep -Fq 'CKERI_PAYER=' <<<"$command"
    grep -Fq 'CKERI_NODE_SOCKET=' <<<"$command"
    grep -Fq 'CKERI_FUNDING_ADDRESS=' <<<"$command"
    grep -Fq 'CKERI_MANIFEST=' <<<"$command"
  done

  grep -Eq '^[$] sudo env .*[/]ckeri register --escrow-lovelace 2000000$' "$transcript"
  grep -Fq "Error: The following scripts have execution failures:" "$transcript"
  grep -Fq \
    "ScriptInfo: MintingScript 0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734" \
    "$transcript"
  grep -Fq \
    "ScriptInfo: RewardingScript (ScriptCredential 3d18237dc14be14284d775a5766016c7c4c432dedce287011701c6c7)" \
    "$transcript"
  grep -Fq "Script language: PlutusV3" "$transcript"
  grep -Fq "Protocol version: Version 11" "$transcript"
  grep -Fq "Caused by: (error)" "$transcript"
  if grep -Fq "Script base64 encoded" "$transcript"; then
    echo "validator evidence must not contain opaque base64 dumps" >&2
    exit 1
  fi

  grep -Fqx \
    "user error (checkpoint already registered; refusing before premint)" \
    "$transcript"
  grep -Eq '^[$] sudo env .*[/]ckeri register --allow-existing-checkpoint$' "$transcript"
  grep -Fqx \
    "warning: sovereign repeat registration creates another fully funded checkpoint copy; the benign residual is intentional" \
    "$transcript"
  grep -Fqx \
    "user error (checkpoint lookup is ambiguous: 2 live outputs)" \
    "$transcript"

  grep -Fqx \
    "user error (declared witnesses have no board record check yet; pass --allow-unlisted-witnesses to acknowledge reduced watchability)" \
    "$transcript"
  grep -Eq '^[$] sudo env .*[/]ckeri register --allow-unlisted-witnesses$' "$transcript"
  grep -Fqx \
    "warning: witness board membership is unverified; accepting reduced public watchability" \
    "$transcript"

  grep -Fqx '$ docker volume rm ckeri-159-acceptance-single-20260728' "$transcript"
  grep -Fqx '$ docker volume rm ckeri-159-acceptance-2of5-20260728' "$transcript"

  if [[ -n "${CKERI_BIN:-}" ]]; then
    check_checkpoint_output "${register_txids[2]}#0" "$multi_aid" "$manifest"

    tx_payload="$(
      printf '%s\n' "${premint_txids[@]}" "${register_txids[@]}" |
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
      length == 6
      and all(.[];
        (.tx_hash | test("^[0-9a-f]{64}$"))
        and (.block_hash | test("^[0-9a-f]{64}$"))
        and (.block_height | type == "number")
      )
    ' <<<"$tx_info" >/dev/null

    echo "M1 registration transcript and six settled transactions are live: OK"
  else
    echo "M1 captured registration transcript is internally consistent: OK"
  fi
)

check_historical_register_base_assertions
