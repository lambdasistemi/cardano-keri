#!/usr/bin/env bash
set -euo pipefail

image="${WITNESS_IMAGE:-cardano-keri-witness:1.3.5}"
ckeri="${CKERI_BIN:?set CKERI_BIN to the packaged ckeri executable}"
workspace="${CKERI_WORKSPACE:-/code/cardano-keri-181-txpath}"
payment_key="${CKERI_PAYMENT_KEY:-/home/paolino/.secrets/cardano-keri-preprod/payment.skey}"
node_socket="${CKERI_NODE_SOCKET:-/code/cardano-preprod/ipc/node.socket}"
funding_address="${CKERI_FUNDING_ADDRESS:-addr_test1vzdqjmt98smx8my6f5uum0szghuy8ff2hep2e64a9w2pehgnv4mdx}"
underfunded_address="${CKERI_UNDERFUNDED_ADDRESS:-addr_test1qzdqjmt98smx8my6f5uum0szghuy8ff2hep2e64a9w2pehty436vwj3d2cslvu2a4aypkrqa4d6ujvldn8l6utg5yyqs4pqv6d}"
manifest="${CKERI_MANIFEST:-$workspace/deploy/preprod/m1-manifest.json}"
board_manifest="${CKERI_BOARD_MANIFEST:-$workspace/deploy/preprod/board-manifest.json}"
output_dir="${CKERI_ACCEPTANCE_DIR:-/tmp/ckeri-181-slice4-acceptance}"
volume="${CKERI_KLI_VOLUME:-ckeri-181-slice4-acceptance}"
base="${CKERI_KLI_BASE:-ckeri-181-slice4}"
underfunded_evidence="${CKERI_UNDERFUNDED_EVIDENCE:?set CKERI_UNDERFUNDED_EVIDENCE to a durable evidence path}"

last_output=""

print_command() {
  printf '$'
  printf ' %q' "$@"
  printf '\n'
}

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

capture_underfunded() {
  local command_line
  command_line="$(print_command "$@")"
  set +e
  last_output="$("$@" 2>&1)"
  local status=$?
  set -e
  {
    printf '%s\n' "$command_line"
    printf '%s\n' "$last_output"
    printf 'exit status: %s\n' "$status"
  } | tee "$underfunded_evidence"
  if ((status == 0)); then
    printf 'underfunded attempt unexpectedly succeeded\n' >&2
    exit 1
  fi
  grep -Eq \
    'RegistrationFundingSelectionFailed (EmptyIndexedSnapshot|[(]InsufficientFundingValue )' \
    "$underfunded_evidence"
  if grep -Eq '(^| )(premint|register|submit|submitted) txid:' \
    "$underfunded_evidence"; then
    printf 'underfunded attempt contains a submission marker\n' >&2
    exit 1
  fi
}

run_kli() {
  capture docker run --rm \
    --volume "$volume:/var/lib/keri/.keri" \
    "$image" "$@"
}

register_command() {
  local address=$1
  shift
  "$ckeri" register \
    --network preprod \
    --network-magic 1 \
    --kel "$output_dir/inception.cesr" \
    --payer "$payment_key" \
    --node-socket "$node_socket" \
    --funding-address "$address" \
    --manifest "$manifest" \
    --board-manifest "$board_manifest" \
    --timeout-seconds 600 \
    "$@"
}

test -r "$payment_key"
test -S "$node_socket"
mkdir -p "$output_dir"
if find "$output_dir" -mindepth 1 -print -quit | grep -q .; then
  printf 'refusing non-empty acceptance directory %s\n' "$output_dir" >&2
  exit 1
fi
if docker volume inspect "$volume" >/dev/null 2>&1; then
  printf 'refusing to reuse Docker volume %s\n' "$volume" >&2
  exit 1
fi

capture date -u +%Y-%m-%dT%H:%M:%SZ
capture "$ckeri" --version
capture docker run --rm "$image" version
capture docker volume create "$volume"
run_kli init --name journey --base "$base" --nopasscode
run_kli incept \
  --name journey \
  --base "$base" \
  --alias journey \
  --transferable \
  --icount 1 \
  --isith 1 \
  --ncount 1 \
  --nsith 1 \
  --toad 0
run_kli status --name journey --base "$base" --alias journey
aid="$(awk '$1 == "Identifier:" {print $2}' <<<"$last_output")"
[[ "$aid" =~ ^E[A-Za-z0-9_-]{43}$ ]]
printf '%s\n' "$aid" >"$output_dir/aid.txt"
capture_shell \
  "docker run --rm --volume $volume:/var/lib/keri/.keri $image export --name journey --base $base --alias journey > $output_dir/inception.cesr"

capture_underfunded \
  register_command "$underfunded_address"
capture register_command "$funding_address"
capture "$ckeri" status \
  --aid "$aid" \
  --manifest "$manifest" \
  --board-manifest "$board_manifest"
