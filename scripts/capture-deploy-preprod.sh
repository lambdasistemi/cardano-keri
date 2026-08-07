#!/usr/bin/env bash
set -euo pipefail

ckeri="${CKERI_BIN:?set CKERI_BIN to the packaged ckeri executable}"
workspace="${CKERI_WORKSPACE:-/code/cardano-keri-181-txpath}"
manifest="${CKERI_MANIFEST:-$workspace/deploy/preprod/m1-manifest.json}"
board_manifest="${CKERI_BOARD_MANIFEST:-$workspace/deploy/preprod/board-manifest.json}"
koios_url="${CKERI_KOIOS_URL:-https://preprod.koios.rest/api/v1}"

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
capture_shell() {
  printf '$ %s\n' "$1"
  set +e
  last_output="$(bash -o pipefail -c "$1" 2>&1)"
  local status=$?
  set -e
  printf '%s\n' "$last_output"
  return "$status"
}

capture date -u +%Y-%m-%dT%H:%M:%SZ
capture "$ckeri" --version
capture jq -r \
  '"deployment mode: verify-only (no reference publication)",
   "source commit: " + .source.commit,
   "blueprint sha256: " + .blueprint.sha256,
   (.scripts[] | "expected reference " + .name + " " + .hash + " " + .reference.txId + "#" + (.reference.index|tostring))' \
  "$manifest"
hashes="$(jq -c '[.scripts[].hash]' "$manifest")"
capture_shell \
  "curl --fail --silent --show-error --request POST $koios_url/reference_script_utxos --header 'Content-Type: application/json' --data '{\"_script_hashes\":$hashes}' | jq -r 'sort_by(.script_hash)[] | \"live reference \\(.script_hash) \\(.tx_hash)#\\(.tx_index)\"'"
test "$(grep -c '^live reference ' <<<"$last_output")" -eq 5
capture jq -r \
  '"board source commit: " + .source.commit,
   "board blueprint sha256: " + .blueprint.sha256,
   "board reference: " + .board.policyId + " " + .board.reference.txId + "#" + (.board.reference.index|tostring)' \
  "$board_manifest"
capture "$ckeri" board list --board-manifest "$board_manifest"
grep -Fq 'board records: 3' <<<"$last_output"
