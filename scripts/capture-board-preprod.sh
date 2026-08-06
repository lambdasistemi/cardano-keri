#!/usr/bin/env bash
set -euo pipefail

phase="${1:?usage: capture-board-preprod.sh post|stranger|lifecycle}"
ckeri="${CKERI_BIN:?set CKERI_BIN to the packaged ckeri executable}"
workspace="${CKERI_WORKSPACE:-/code/cardano-keri-181-txpath}"
payment_key="${CKERI_PAYMENT_KEY:-/home/paolino/.secrets/cardano-keri-preprod/payment.skey}"
node_socket="${CKERI_NODE_SOCKET:-/code/cardano-preprod/ipc/node.socket}"
funding_address="${CKERI_FUNDING_ADDRESS:-addr_test1vzdqjmt98smx8my6f5uum0szghuy8ff2hep2e64a9w2pehgnv4mdx}"
refund_address="${CKERI_REFUND_ADDRESS:-addr_test1qzdqjmt98smx8my6f5uum0szghuy8ff2hep2e64a9w2pehty436vwj3d2cslvu2a4aypkrqa4d6ujvldn8l6utg5yyqs4pqv6d}"
board_manifest="${CKERI_BOARD_MANIFEST:-$workspace/deploy/preprod/board-manifest.json}"
output_dir="${CKERI_ACCEPTANCE_DIR:-/tmp/ckeri-181-slice4-acceptance}"
witness="BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI"
oobi="https://witness-1.preprod.plutimus.com/oobi/$witness/controller"

last_output=""
print_command() { printf '$'; printf ' %q' "$@"; printf '\n'; }
capture() {
  print_command "$@"
  set +e
  last_output="$("$@" 2>&1)"
  local status=$?
  set -e
  printf '%s\n' "$last_output"
  return "$status"
}

transaction_args=(
  --network preprod
  --network-magic 1
  --payer "$payment_key"
  --node-socket "$node_socket"
  --funding-address "$funding_address"
  --change-address "$funding_address"
  --board-manifest "$board_manifest"
  --timeout-seconds 600
)

mkdir -p "$output_dir"
case "$phase" in
  post)
    capture date -u +%Y-%m-%dT%H:%M:%SZ
    capture "$ckeri" --version
    capture "$ckeri" board list --board-manifest "$board_manifest"
    grep -Fq 'board records: 3' <<<"$last_output"
    capture curl --fail --silent --show-error \
      --output "$output_dir/witness-1-oobi.cesr" "$oobi"
    capture wc -c "$output_dir/witness-1-oobi.cesr"
    capture "$ckeri" board post \
      --endpoint-record "$output_dir/witness-1-oobi.cesr" \
      "${transaction_args[@]}"
    post_txid="$(sed -n 's/^board txid: \([0-9a-f]\{64\}\) deposit: 4 tADA$/\1/p' <<<"$last_output")"
    [[ "$post_txid" =~ ^[0-9a-f]{64}$ ]]
    printf '%s\n' "$post_txid" >"$output_dir/board-post-txid.txt"
    capture "$ckeri" board list --board-manifest "$board_manifest"
    grep -Fq 'board records: 4' <<<"$last_output"
    ;;
  stranger)
    test -f "$output_dir/board-post-txid.txt"
    capture date -u +%Y-%m-%dT%H:%M:%SZ
    capture curl --fail --silent --show-error \
      --output /dev/null \
      --write-out 'HTTP %{http_code} bytes %{size_download}\n' \
      "$oobi"
    capture "$ckeri" board list --board-manifest "$board_manifest"
    grep -Fq 'board records: 4' <<<"$last_output"
    ;;
  lifecycle)
    post_txid="$(<"$output_dir/board-post-txid.txt")"
    [[ "$post_txid" =~ ^[0-9a-f]{64}$ ]]
    capture date -u +%Y-%m-%dT%H:%M:%SZ
    capture "$ckeri" board update \
      --endpoint-record "$output_dir/witness-1-oobi.cesr" \
      --board-out-ref "$post_txid#0" \
      "${transaction_args[@]}"
    update_txid="$(sed -n 's/^board update txid: \([0-9a-f]\{64\}\)$/\1/p' <<<"$last_output")"
    [[ "$update_txid" =~ ^[0-9a-f]{64}$ ]]
    capture "$ckeri" board list --board-manifest "$board_manifest"
    grep -Fq 'board records: 4' <<<"$last_output"
    grep -Fq "$update_txid#0" <<<"$last_output"
    capture "$ckeri" board retire \
      --witness "$witness" \
      --board-out-ref "$update_txid#0" \
      --to "$refund_address" \
      "${transaction_args[@]}"
    capture "$ckeri" board list --board-manifest "$board_manifest"
    grep -Fq 'board records: 3' <<<"$last_output"
    if grep -Fq "$post_txid#0" <<<"$last_output" || \
      grep -Fq "$update_txid#0" <<<"$last_output"; then
      printf 'temporary board record survived retirement\n' >&2
      exit 1
    fi
    ;;
  *)
    printf 'unknown board capture phase: %s\n' "$phase" >&2
    exit 2
    ;;
esac
