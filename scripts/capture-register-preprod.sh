#!/usr/bin/env bash
set -euo pipefail

image="${WITNESS_IMAGE:-cardano-keri-witness:1.3.5}"
ckeri="${CKERI_BIN:?set CKERI_BIN to the packaged ckeri executable}"
workspace="${CKERI_WORKSPACE:-/tmp/ckeri-159-src}"
payment_key="${CKERI_PAYMENT_KEY:-/home/paolino/secrets/cardano-keri-preprod/payment.skey}"
node_socket="${CKERI_NODE_SOCKET:-/node/preprod/ipc/node.socket}"
funding_address="${CKERI_FUNDING_ADDRESS:-addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d}"
manifest="${CKERI_MANIFEST:-$workspace/deploy/preprod/m1-manifest.json}"
output_dir="${CKERI_ACCEPTANCE_DIR:-/tmp/ckeri-159-acceptance}"
single_volume="${CKERI_SINGLE_VOLUME:-ckeri-159-acceptance-single-20260728}"
multi_volume="${CKERI_MULTI_VOLUME:-ckeri-159-acceptance-2of5-20260728}"
single_base="${CKERI_SINGLE_BASE:-ckeri-159-acceptance-single}"
multi_base="${CKERI_MULTI_BASE:-ckeri-159-acceptance-2of5}"

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
  local volume=$1
  shift
  capture docker run --rm \
    --volume "$volume:/var/lib/keri/.keri" \
    "$image" "$@"
}

register_capture() {
  local kel=$1
  shift
  capture sudo env \
    CKERI_NETWORK=preprod \
    CKERI_NETWORK_MAGIC=1 \
    CKERI_KEL="$kel" \
    CKERI_PAYER="$payment_key" \
    CKERI_NODE_SOCKET="$node_socket" \
    CKERI_FUNDING_ADDRESS="$funding_address" \
    CKERI_MANIFEST="$manifest" \
    "$ckeri" register \
    "$@"
}

register_failure() {
  local kel=$1
  shift
  capture_failure sudo env \
    CKERI_NETWORK=preprod \
    CKERI_NETWORK_MAGIC=1 \
    CKERI_KEL="$kel" \
    CKERI_PAYER="$payment_key" \
    CKERI_NODE_SOCKET="$node_socket" \
    CKERI_FUNDING_ADDRESS="$funding_address" \
    CKERI_MANIFEST="$manifest" \
    "$ckeri" register \
    "$@"
}

status_capture() {
  capture "$ckeri" status "$1" --manifest "$manifest"
}

rm -rf "$output_dir"
mkdir -p "$output_dir"
docker volume inspect "$single_volume" >/dev/null 2>&1 && {
  printf 'refusing to reuse Docker volume %s\n' "$single_volume" >&2
  exit 1
}
docker volume inspect "$multi_volume" >/dev/null 2>&1 && {
  printf 'refusing to reuse Docker volume %s\n' "$multi_volume" >&2
  exit 1
}

capture "$ckeri" --version
capture docker run --rm "$image" version

capture docker volume create "$single_volume"
run_kli "$single_volume" init \
  --name stranger \
  --base "$single_base" \
  --nopasscode
run_kli "$single_volume" incept \
  --name stranger \
  --base "$single_base" \
  --alias stranger \
  --transferable \
  --icount 1 \
  --isith 1 \
  --ncount 1 \
  --nsith 1 \
  --toad 0
run_kli "$single_volume" status \
  --name stranger \
  --base "$single_base" \
  --alias stranger
single_aid="$(awk '$1 == "Identifier:" {print $2}' <<<"$last_output")"
test -n "$single_aid"
capture_shell \
  "docker run --rm --volume $single_volume:/var/lib/keri/.keri $image export --name stranger --base $single_base --alias stranger > $output_dir/single.cesr"
status_capture "$single_aid"
register_failure \
  "$output_dir/single.cesr" \
  --escrow-lovelace 2000000
register_capture "$output_dir/single.cesr"
status_capture "$single_aid"
register_failure "$output_dir/single.cesr"
register_capture \
  "$output_dir/single.cesr" \
  --allow-existing-checkpoint
capture_failure "$ckeri" status "$single_aid" --manifest "$manifest"

capture docker volume create "$multi_volume"
run_kli "$multi_volume" init \
  --name org \
  --base "$multi_base" \
  --nopasscode
run_kli "$multi_volume" oobi resolve \
  --name org \
  --base "$multi_base" \
  --oobi "$oobi_1" \
  --oobi-alias witness-1
run_kli "$multi_volume" oobi resolve \
  --name org \
  --base "$multi_base" \
  --oobi "$oobi_2" \
  --oobi-alias witness-2
run_kli "$multi_volume" oobi resolve \
  --name org \
  --base "$multi_base" \
  --oobi "$oobi_3" \
  --oobi-alias witness-3
run_kli "$multi_volume" incept \
  --name org \
  --base "$multi_base" \
  --alias org \
  --transferable \
  --icount 5 \
  --isith 2 \
  --ncount 5 \
  --nsith 2 \
  --wits "$witness_1" \
  --wits "$witness_2" \
  --wits "$witness_3" \
  --toad 2
run_kli "$multi_volume" status \
  --name org \
  --base "$multi_base" \
  --alias org
multi_aid="$(awk '$1 == "Identifier:" {print $2}' <<<"$last_output")"
test -n "$multi_aid"
capture_shell \
  "docker run --rm --volume $multi_volume:/var/lib/keri/.keri $image export --name org --base $multi_base --alias org > $output_dir/2-of-5.cesr"
status_capture "$multi_aid"
register_failure "$output_dir/2-of-5.cesr"
register_capture \
  "$output_dir/2-of-5.cesr" \
  --allow-unlisted-witnesses
status_capture "$multi_aid"

capture docker volume rm "$single_volume"
capture docker volume rm "$multi_volume"
