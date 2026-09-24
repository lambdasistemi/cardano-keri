#!/usr/bin/env bash
set -euo pipefail

# A fresh, funded preprod V1 journey. Never publish a cast unless it completes.
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ckeri_bin=${CKERI_BIN:?set CKERI_BIN to a compatible V1 ckeri with register and close}
deploy_ckeri_bin=${DEPLOY_CKERI_BIN:?set DEPLOY_CKERI_BIN to ckeri built from manifest source commit}
witness_image=${WITNESS_IMAGE:-cardano-keri-witness:1.3.5}
export CKERI_NETWORK=preprod CKERI_NETWORK_MAGIC=1
export CKERI_PAYER=${CKERI_PAYER:?set CKERI_PAYER to the preprod payment key}
export CKERI_NODE_SOCKET=${CKERI_NODE_SOCKET:?set CKERI_NODE_SOCKET to the preprod node socket}
export CKERI_FUNDING_ADDRESS=${CKERI_FUNDING_ADDRESS:?set CKERI_FUNDING_ADDRESS to a funded preprod address}
export CKERI_CHANGE_ADDRESS=${CKERI_CHANGE_ADDRESS:?set CKERI_CHANGE_ADDRESS to a distinct address controlled by the payer}
export CKERI_TO=${CKERI_TO:-$CKERI_FUNDING_ADDRESS}
export CKERI_MANIFEST=${CKERI_MANIFEST:-$repo_root/deploy/preprod/m1-manifest.json}
export CKERI_BOARD_MANIFEST=${CKERI_BOARD_MANIFEST:-$repo_root/deploy/preprod/board-manifest.json}
export CKERI_TIMEOUT_SECONDS=${CKERI_TIMEOUT_SECONDS:-600}
run_dir=$(mktemp -d "${DEMO_RUN_PARENT:-/tmp}/ckeri-preprod-demo.XXXXXX")
chmod 700 "$run_dir"
run_name=$(basename "$run_dir" | tr . -)
volume="${run_name}-keripy"
base="$run_name"
pause_ms=${DEMO_PAUSE_MS:-3500}
[[ "$pause_ms" =~ ^[0-9]+$ ]] && (( pause_ms <= 10000 ))
test -r "$CKERI_PAYER"
test -S "$CKERI_NODE_SOCKET"
test -r "$CKERI_MANIFEST"
test "$CKERI_CHANGE_ADDRESS" != "$CKERI_TO"
perl -MIO::Socket::UNIX -e '
  $s=IO::Socket::UNIX->new(Peer=>$ARGV[0]) or die "node socket refused: $!\n";
' "$CKERI_NODE_SOCKET"
docker image inspect "$witness_image" >/dev/null
docker volume inspect "$volume" >/dev/null 2>&1 && {
  printf 'refusing existing keripy volume %s\n' "$volume" >&2
  exit 1
}

reset=$'\033[0m' cyan=$'\033[1;36m' dim=$'\033[0;90m'
green=$'\033[1;32m' yellow=$'\033[1;33m'
frame() {
  printf '\033[H\033[2J\033[3J%s%s%s\n\n%s# %s%s\n\n' \
    "$cyan" "$1" "$reset" "$dim" "$2" "$reset"
}
pause() { sleep "$(awk -v ms="$pause_ms" 'BEGIN { printf "%.3f", ms / 1000 }')"; }
ckeri() { "$ckeri_bin" "$@"; }
kli() { docker run --rm --volume "$volume:/var/lib/keri/.keri" "$witness_image" "$@"; }
run() {
  printf '%s$' "$green"
  printf ' %q' "$@"
  printf '%s\n' "$reset"
  "$@"
}
status() {
  run ckeri status --aid "$aid" --manifest "$CKERI_MANIFEST" \
    --board-manifest "$CKERI_BOARD_MANIFEST"
}
print_receipt() {
  local label=$1 txid=$2
  [[ "$txid" =~ ^[0-9a-f]{64}$ ]]
  printf '%s%s tx: %s%s\n' "$yellow" "$label" "$txid" "$reset"
}

frame 'Preprod V1 | release and network' \
  'This is the deployed V1 checkpoint, not the planned Singular registry.'
printf '%s$ ckeri manifest verify --manifest m1-manifest.json --koios-url preprod%s\n' "$green" "$reset"
"$deploy_ckeri_bin" manifest verify --manifest "$CKERI_MANIFEST" \
  --source-repo "${DEPLOY_SOURCE_REPO:?set DEPLOY_SOURCE_REPO to manifest source checkout}" \
  --koios-url https://preprod.koios.rest/api/v1 | tail -n 2
run ckeri --version
run kli version
pause

frame 'Alice creates a KERI identifier' \
  'Keripy owns the keys. The AID and CESR export are fresh for this run.'
run docker volume create "$volume" >/dev/null
run kli init --name alice --base "$base" --nopasscode
run kli incept --name alice --base "$base" --alias alice --transferable \
  --icount 1 --isith 1 --ncount 1 --nsith 1 --toad 0
alice_status=$(kli status --name alice --base "$base" --alias alice)
aid=$(awk '$1 == "Identifier:" {print $2}' <<<"$alice_status")
[[ "$aid" =~ ^E[A-Za-z0-9_-]{43}$ ]]
printf '%s\n' "$alice_status"
printf '%s$ kli export --name alice --alias alice > inception.cesr%s\n' "$green" "$reset"
kli export --name alice --base "$base" --alias alice >"$run_dir/inception.cesr"
test -s "$run_dir/inception.cesr"
pause

frame 'Alice registers on Cardano preprod' \
  'ckeri consumes the keripy export and settles the V1 checkpoint.'
printf '%s$ ckeri register --network preprod --kel inception.cesr%s\n' "$green" "$reset"
register_output=$(ckeri register --network preprod --network-magic 1 \
  --kel "$run_dir/inception.cesr" --manifest "$CKERI_MANIFEST" \
  --board-manifest "$CKERI_BOARD_MANIFEST")
printf '%s\n' "$register_output"
register_tx=$(awk '$1 == "register" && $2 == "txid:" {print $3}' <<<"$register_output")
print_receipt register "$register_tx"
pause

frame 'Independent checkpoint readback' \
  'Status must name the same AID and settled registration transaction.'
printf '%s$ ckeri status --aid %s%s\n' "$green" "$aid" "$reset"
registered_status=$(ckeri status --aid "$aid" --manifest "$CKERI_MANIFEST" \
  --board-manifest "$CKERI_BOARD_MANIFEST")
grep -Fq "aid $aid state ACTIVE seq 0" <<<"$registered_status"
grep -Fq "tx $register_tx#" <<<"$registered_status"
printf '%s\n' "$registered_status"
pause

frame 'Alice prepares her V1 close' \
  'The refund destination is fixed in the signed close package.'
printf '%s$ ckeri close --aid %s --kel inception.cesr --signing-package close-package%s\n' \
  "$green" "$aid" "$reset"
ckeri close --network preprod --network-magic 1 --aid "$aid" \
  --kel "$run_dir/inception.cesr" --to "$CKERI_TO" \
  --manifest "$CKERI_MANIFEST" --signing-package "$run_dir/close-package"
chmod 0777 "$run_dir" "$run_dir/close-package"
printf '%s$ kli-sign-close --package close-package%s\n' "$green" "$reset"
docker run --rm --volume "$volume:/var/lib/keri/.keri" \
  --volume "$run_dir:/demo" \
  --volume "$repo_root/scripts/kli-sign-close.py:/usr/local/bin/kli-sign-close.py:ro" \
  --entrypoint python "$witness_image" /usr/local/bin/kli-sign-close.py \
  --name alice --base "$base" --alias alice \
  --package /demo/close-package --out /demo/close-signatures.cesr
test -s "$run_dir/close-signatures.cesr"
pause

frame 'Alice closes and reads back' \
  'ckeri submits the signed close; status must no longer find an active checkpoint.'
printf '%s$ ckeri close --aid %s --controller-signatures close-signatures.cesr%s\n' \
  "$green" "$aid" "$reset"
close_output=$(ckeri close --network preprod --network-magic 1 --aid "$aid" \
  --kel "$run_dir/inception.cesr" --to "$CKERI_TO" \
  --manifest "$CKERI_MANIFEST" \
  --controller-signatures "$run_dir/close-signatures.cesr")
printf '%s\n' "$close_output"
close_tx=$(awk '$1 == "close" && $2 == "txid:" {print $3}' <<<"$close_output")
print_receipt close "$close_tx"
printf '%s$ ckeri status --aid %s%s\n' "$green" "$aid" "$reset"
closed_status=$(ckeri status --aid "$aid" --manifest "$CKERI_MANIFEST" \
  --board-manifest "$CKERI_BOARD_MANIFEST")
grep -Fq "aid $aid state NOT REGISTERED" <<<"$closed_status"
printf '%s\n' "$closed_status"
printf '%sAID %s; register %s; close %s%s\n' \
  "$yellow" "$aid" "$register_tx" "$close_tx" "$reset"
printf '%sreceipt directory: %s%s\n' "$dim" "$run_dir" "$reset"
docker volume rm "$volume" >/dev/null
pause
