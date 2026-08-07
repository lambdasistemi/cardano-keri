#!/usr/bin/env bash
set -euo pipefail

image="${WITNESS_IMAGE:-cardano-keri-witness:1.3.5}"
ckeri="${CKERI_BIN:?set CKERI_BIN to the packaged ckeri executable}"
workspace="${CKERI_WORKSPACE:-/code/cardano-keri-181-txpath}"
payment_key="${CKERI_PAYMENT_KEY:-/home/paolino/.secrets/cardano-keri-preprod/payment.skey}"
node_socket="${CKERI_NODE_SOCKET:-/code/cardano-preprod/ipc/node.socket}"
funding_address="${CKERI_FUNDING_ADDRESS:-addr_test1vzdqjmt98smx8my6f5uum0szghuy8ff2hep2e64a9w2pehgnv4mdx}"
manifest="${CKERI_MANIFEST:-$workspace/deploy/preprod/m1-manifest.json}"
board_manifest="${CKERI_BOARD_MANIFEST:-$workspace/deploy/preprod/board-manifest.json}"
output_dir="${CKERI_ACCEPTANCE_DIR:-/tmp/ckeri-181-slice4-acceptance}"
volume="${CKERI_KLI_VOLUME:-ckeri-181-slice4-acceptance}"
base="${CKERI_KLI_BASE:-ckeri-181-slice4}"

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
run_kli() {
  capture docker run --rm \
    --volume "$volume:/var/lib/keri/.keri" \
    "$image" "$@"
}

aid="$(<"$output_dir/aid.txt")"
[[ "$aid" =~ ^E[A-Za-z0-9_-]{43}$ ]]
docker volume inspect "$volume" >/dev/null
test -f "$output_dir/inception.cesr"

capture date -u +%Y-%m-%dT%H:%M:%SZ
capture "$ckeri" --version
capture "$ckeri" status \
  --aid "$aid" \
  --manifest "$manifest" \
  --board-manifest "$board_manifest"
run_kli rotate \
  --name journey \
  --base "$base" \
  --alias journey \
  --next-count 1 \
  --isith 1 \
  --nsith 1 \
  --toad 0
run_kli status --name journey --base "$base" --alias journey
capture_shell \
  "docker run --rm --volume $volume:/var/lib/keri/.keri $image export --name journey --base $base --alias journey > $output_dir/rotation.cesr"
capture "$ckeri" advance \
  --network preprod \
  --network-magic 1 \
  --aid "$aid" \
  --kel "$output_dir/rotation.cesr" \
  --manifest "$manifest" \
  --signing-package "$output_dir/advance-package"
capture chmod 0777 "$output_dir" "$output_dir/advance-package"
capture docker run --rm \
  --volume "$volume:/var/lib/keri/.keri" \
  --volume "$output_dir:/acceptance" \
  --volume "$workspace/scripts/kli-sign-advance.py:/usr/local/bin/kli-sign-advance.py:ro" \
  --entrypoint python \
  "$image" \
  /usr/local/bin/kli-sign-advance.py \
  --name journey \
  --base "$base" \
  --alias journey \
  --package /acceptance/advance-package \
  --out /acceptance/advance-signatures.cesr

# The immutable M1 observer predates #219 and verifies the legacy,
# Cardano-domain AdvanceMessage. For a 1-of-1 capture, this acceptance-only
# switch bypasses the newer local native-event rule without weakening the
# deployed validator; the real reference script still evaluates the evidence.
capture "$ckeri" advance \
  --network preprod \
  --network-magic 1 \
  --aid "$aid" \
  --kel "$output_dir/rotation.cesr" \
  --manifest "$manifest" \
  --controller-signatures "$output_dir/advance-signatures.cesr" \
  --payer "$payment_key" \
  --node-socket "$node_socket" \
  --funding-address "$funding_address" \
  --timeout-seconds 600 \
  --validator-test-under-signed
capture "$ckeri" status \
  --aid "$aid" \
  --manifest "$manifest" \
  --board-manifest "$board_manifest"
