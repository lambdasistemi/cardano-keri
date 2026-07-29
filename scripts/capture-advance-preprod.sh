#!/usr/bin/env bash
set -euo pipefail

if [[ -t 1 ]]; then
  stty -onlcr
fi

image="${WITNESS_IMAGE:-cardano-keri-witness:1.3.5}"
ckeri="${CKERI_BIN:?set CKERI_BIN to the packaged ckeri executable}"
workspace="${CKERI_WORKSPACE:-/tmp/ckeri-160-src}"
payment_key="${CKERI_PAYMENT_KEY:-/home/paolino/secrets/cardano-keri-preprod/payment.skey}"
node_socket="${CKERI_NODE_SOCKET:-/node/preprod/ipc/node.socket}"
funding_address="${CKERI_FUNDING_ADDRESS:-addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d}"
manifest="${CKERI_MANIFEST:-$workspace/deploy/preprod/m1-manifest.json}"
output_dir="${CKERI_ACCEPTANCE_DIR:-/tmp/ckeri-160-acceptance}"
volume="${CKERI_KLI_VOLUME:-ckeri-160-acceptance-2of5-20260729}"
base="${CKERI_KLI_BASE:-ckeri-160-acceptance-2of5}"
resume="${CKERI_ACCEPTANCE_RESUME:-0}"

witness_1="BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI"
witness_2="BBkK9o9mMm_nIu5yl3x3L7ti8cYoKg-AoxpqQapMcE5B"
witness_3="BNP31dFWbqS_oUe2CUu24Ct7cQjpk3DscLzbpGT5OEz4"
oobi_1="https://witness-1.preprod.plutimus.com/oobi/$witness_1/controller"
oobi_2="https://witness-2.preprod.plutimus.com/oobi/$witness_2/controller"
oobi_3="https://witness-3.preprod.plutimus.com/oobi/$witness_3/controller"

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
  if ((status != 0)); then
    return "$status"
  fi
}

capture_shell() {
  printf '$ %s\n' "$1"
  set +e
  last_output="$(bash -o pipefail -c "$1" 2>&1)"
  local status=$?
  set -e
  printf '%s\n' "$last_output"
  if ((status != 0)); then
    return "$status"
  fi
}

capture_failure() {
  print_command "$@"
  set +e
  last_output="$("$@" 2>&1)"
  local status=$?
  set -e
  printf '%s\n' "$last_output"
  if ((status == 0)); then
    printf 'expected command to fail but it exited zero\n' >&2
    exit 1
  fi
}

run_kli() {
  local requested_volume=$1
  shift
  capture docker run --rm \
    --volume "$requested_volume:/var/lib/keri/.keri" \
    "$image" "$@"
}

status_capture() {
  capture "$ckeri" status "$1" --manifest "$manifest"
}

register_capture() {
  capture sudo env \
    CKERI_NETWORK=preprod \
    CKERI_NETWORK_MAGIC=1 \
    CKERI_KEL="$output_dir/inception.cesr" \
    CKERI_PAYER="$payment_key" \
    CKERI_NODE_SOCKET="$node_socket" \
    CKERI_FUNDING_ADDRESS="$funding_address" \
    CKERI_MANIFEST="$manifest" \
    "$ckeri" register \
    --allow-unlisted-witnesses
}

advance_prepare() {
  capture "$ckeri" advance \
    --network preprod \
    --network-magic 1 \
    --aid "$1" \
    --kel "$output_dir/rotation.cesr" \
    --manifest "$manifest" \
    --signing-package "$output_dir/package"
}

advance_failure() {
  local aid=$1
  shift
  capture_failure sudo env \
    CKERI_PAYER="$payment_key" \
    CKERI_NODE_SOCKET="$node_socket" \
    CKERI_FUNDING_ADDRESS="$funding_address" \
    "$ckeri" advance \
    --network preprod \
    --network-magic 1 \
    --aid "$aid" \
    --kel "$output_dir/rotation.cesr" \
    --manifest "$manifest" \
    --controller-signatures "$output_dir/controller-signatures.cesr" \
    "$@"
}

advance_capture() {
  local aid=$1
  capture sudo env \
    CKERI_PAYER="$payment_key" \
    CKERI_NODE_SOCKET="$node_socket" \
    CKERI_FUNDING_ADDRESS="$funding_address" \
    "$ckeri" advance \
    --network preprod \
    --network-magic 1 \
    --aid "$aid" \
    --kel "$output_dir/rotation.cesr" \
    --manifest "$manifest" \
    --controller-signatures "$output_dir/controller-signatures.cesr"
}

sign_and_finish() {
  local aid=$1
  capture chmod 0777 "$output_dir"
  capture docker run --rm \
    --volume "$volume:/var/lib/keri/.keri" \
    --volume "$output_dir:/acceptance" \
    --volume "$workspace/scripts/kli-sign-advance.py:/usr/local/bin/kli-sign-advance.py:ro" \
    --entrypoint python \
    "$image" \
    /usr/local/bin/kli-sign-advance.py \
    --name org \
    --base "$base" \
    --alias org \
    --package /acceptance/package \
    --out /acceptance/controller-signatures.cesr

  advance_failure "$aid" --validator-test-under-signed
  advance_failure "$aid" --validator-test-under-witnessed
  advance_capture "$aid"
  status_capture "$aid"
  advance_failure "$aid" --validator-test-stale

  capture docker volume rm "$volume"
}

if [[ "$resume" == 1 ]]; then
  docker volume inspect "$volume" >/dev/null
  test -f "$output_dir/rotation.cesr"
  test -f "$output_dir/package/package.json"
  run_kli "$volume" status \
    --name org \
    --base "$base" \
    --alias org
  aid="$(awk '$1 == "Identifier:" {print $2}' <<<"$last_output")"
  test -n "$aid"
  sign_and_finish "$aid"
  exit
fi

mkdir -p "$output_dir"
if find "$output_dir" -mindepth 1 -print -quit | grep -q .; then
  printf 'refusing non-empty acceptance directory %s\n' "$output_dir" >&2
  exit 1
fi
docker volume inspect "$volume" >/dev/null 2>&1 && {
  printf 'refusing to reuse Docker volume %s\n' "$volume" >&2
  exit 1
}

capture "$ckeri" --version
capture docker run --rm "$image" version
capture docker volume create "$volume"
run_kli "$volume" init \
  --name org \
  --base "$base" \
  --nopasscode
run_kli "$volume" oobi resolve \
  --name org \
  --base "$base" \
  --oobi "$oobi_1" \
  --oobi-alias witness-1
run_kli "$volume" oobi resolve \
  --name org \
  --base "$base" \
  --oobi "$oobi_2" \
  --oobi-alias witness-2
run_kli "$volume" oobi resolve \
  --name org \
  --base "$base" \
  --oobi "$oobi_3" \
  --oobi-alias witness-3
run_kli "$volume" incept \
  --name org \
  --base "$base" \
  --alias org \
  --transferable \
  --icount 5 \
  --isith 2 \
  --ncount 5 \
  --nsith 2 \
  --wits "$witness_1" \
  --wits "$witness_2" \
  --wits "$witness_3" \
  --toad 2 \
  --receipt-endpoint
run_kli "$volume" status \
  --name org \
  --base "$base" \
  --alias org
aid="$(awk '$1 == "Identifier:" {print $2}' <<<"$last_output")"
test -n "$aid"
capture_shell \
  "docker run --rm --volume $volume:/var/lib/keri/.keri $image export --name org --base $base --alias org > $output_dir/inception.cesr"
status_capture "$aid"
register_capture
status_capture "$aid"

run_kli "$volume" rotate \
  --name org \
  --base "$base" \
  --alias org \
  --next-count 5 \
  --isith 2 \
  --nsith 2 \
  --toad 2 \
  --receipt-endpoint
run_kli "$volume" status \
  --name org \
  --base "$base" \
  --alias org
capture_shell \
  "docker run --rm --volume $volume:/var/lib/keri/.keri $image export --name org --base $base --alias org > $output_dir/rotation.cesr"
advance_prepare "$aid"
sign_and_finish "$aid"
