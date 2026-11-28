#!/usr/bin/env bash
set -euo pipefail

ckeri="$(realpath -- "${1:?usage: check-ckeri-cli.sh CKERI}")"
worktree="$(pwd -P)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
outside="$workspace/outside-checkout"
mkdir "$outside"

"$worktree/scripts/check-ckeri-closure-no-cli.sh" "$ckeri"

"$ckeri" --help | grep -q "deploy"
"$ckeri" --help | grep -q "manifest"
"$ckeri" --help | grep -q "register"
"$ckeri" --help | grep -q "advance"
"$ckeri" --help | grep -q "freeze"
"$ckeri" --help | grep -q "top-up"
"$ckeri" --help | grep -q "status"
"$ckeri" deploy --help | grep -q -- "--node-socket"
"$ckeri" deploy --help | grep -q "CKERI_NODE_SOCKET"
"$ckeri" manifest verify --help | grep -q -- "--manifest"
"$ckeri" manifest verify --help | grep -q "CKERI_MANIFEST"
"$ckeri" manifest verify --help | grep -q -- "--koios-token"
"$ckeri" manifest verify --help | grep -q "KOIOS_TOKEN"
"$ckeri" register --help | grep -q -- "--kel"
"$ckeri" register --help | grep -q "CKERI_KEL"
"$ckeri" register --help | grep -q -- "--payer"
"$ckeri" register --help | grep -q "CKERI_PAYER"
"$ckeri" register --help | grep -q "allow-unlisted-witnesses"
"$ckeri" register --help | grep -q "CKERI_ALLOW_UNLISTED_WITNESSES"
"$ckeri" register --help | grep -q "allow-existing-checkpoint"
"$ckeri" register --help | grep -q "CKERI_ALLOW_EXISTING_CHECKPOINT"
"$ckeri" register --help | grep -q -- "--board-manifest"
"$ckeri" register --help | grep -q "CKERI_BOARD_MANIFEST"
"$ckeri" advance --help | grep -q -- "--aid"
"$ckeri" advance --help | grep -q "CKERI_AID"
"$ckeri" advance --help | grep -q -- "--kel"
"$ckeri" advance --help | grep -q "CKERI_KEL"
"$ckeri" advance --help | grep -q -- "--signing-package"
"$ckeri" advance --help | grep -q "CKERI_SIGNING_PACKAGE"
"$ckeri" advance --help | grep -q -- "--controller-signatures"
"$ckeri" advance --help | grep -q "CKERI_CONTROLLER_SIGNATURES"
"$ckeri" advance --help | grep -q -- "--payer"
"$ckeri" advance --help | grep -q "CKERI_PAYER"
"$ckeri" advance --help | grep -q -- "--deposit"
"$ckeri" advance --help | grep -q "CKERI_DEPOSIT"
"$ckeri" advance --help | grep -q -- "--deposit-signatures"
"$ckeri" advance --help | grep -q "CKERI_DEPOSIT_SIGNATURES"
"$ckeri" advance --help | grep -q "validator-test-under-signed"
"$ckeri" advance --help | grep -q "validator-test-under-witnessed"
"$ckeri" advance --help | grep -q "validator-test-stale"
"$ckeri" freeze --help | grep -q -- "--aid"
"$ckeri" freeze --help | grep -q "CKERI_AID"
"$ckeri" freeze --help | grep -q -- "--kel"
"$ckeri" freeze --help | grep -q "CKERI_KEL"
"$ckeri" freeze --help | grep -q -- "--payer"
"$ckeri" freeze --help | grep -q "CKERI_PAYER"
"$ckeri" freeze --help | grep -q -- "--funding-address"
"$ckeri" freeze --help | grep -q "CKERI_FUNDING_ADDRESS"
"$ckeri" top-up --help | grep -q -- "--aid"
"$ckeri" top-up --help | grep -q "CKERI_AID"
"$ckeri" top-up --help | grep -q -- "--amount"
"$ckeri" top-up --help | grep -q "CKERI_AMOUNT"
"$ckeri" top-up --help | grep -q -- "--payer"
"$ckeri" top-up --help | grep -q "CKERI_PAYER"
"$ckeri" top-up --help | grep -q -- "--funding-address"
"$ckeri" top-up --help | grep -q "CKERI_FUNDING_ADDRESS"
"$ckeri" status --help | grep -q "AID"
"$ckeri" status --help | grep -q "CKERI_AID"
"$ckeri" status --help | grep -q -- "--koios-token"
"$ckeri" status --help | grep -q "KOIOS_TOKEN"
"$ckeri" status --help | grep -q -- "--board-manifest"
"$ckeri" status --help | grep -q "CKERI_BOARD_MANIFEST"
"$ckeri" board post --help | grep -q "default: 4000000"

# A checkpoint is alive until it is convicted: the packaged parser must
# report close and reopen as unrecognised commands. advance is recognised
# (it fails only for its missing options) and an invented name is refused
# the same way, so the detection is shown able to answer both ways.
parser_verdict() {
  local output
  output="$("$ckeri" "$1" 2>&1 || true)"
  if sed 's/\x1b\[[0-9;]*m//g' <<<"$output" | grep -qF "Unrecognised command: $1"; then
    echo unrecognised
  else
    echo recognised
  fi
}

expect_parser_verdict() {
  local actual
  actual="$(parser_verdict "$1")"
  if [[ "$actual" != "$2" ]]; then
    printf 'ckeri %s: expected the parser to answer %s, got %s\n' \
      "$1" "$2" "$actual" >&2
    exit 1
  fi
}

expect_parser_verdict close unrecognised
expect_parser_verdict reopen unrecognised
expect_parser_verdict no-such-command unrecognised
expect_parser_verdict advance recognised
expect_parser_verdict freeze recognised
expect_parser_verdict top-up recognised

reject_retired_cardano_cli_help() {
  local command_label="$1"
  shift
  local help
  help="$("$ckeri" "$@" --help)"
  if grep -q -- '--cardano-cli\|CKERI_CARDANO_CLI' <<<"$help"; then
    printf '%s help still exposes retired cardano-cli configuration\n' \
      "$command_label" >&2
    exit 1
  fi
}

reject_retired_cardano_cli_help deploy deploy
reject_retired_cardano_cli_help register register
reject_retired_cardano_cli_help advance advance
reject_retired_cardano_cli_help freeze freeze
reject_retired_cardano_cli_help top-up top-up
reject_retired_cardano_cli_help board-deploy board deploy
reject_retired_cardano_cli_help board-post board post
reject_retired_cardano_cli_help board-update board update
reject_retired_cardano_cli_help board-retire board retire

# #240 (INV-240-NOPROVIDER): every migrated write command's help surface
# must omit provider (Koios) configuration -- the read-only commands
# (manifest verify, status) keep their own --koios-token/KOIOS_TOKEN
# assertions above as the positive control proving this detection method
# can find a real Koios surface when one is actually present.
reject_write_koios_help() {
  local command_label="$1"
  shift
  local help
  help="$("$ckeri" "$@" --help)"
  if grep -q -- '--koios-token\|KOIOS_TOKEN' <<<"$help"; then
    printf '%s help still exposes provider (Koios) configuration (#240 INV-240-NOPROVIDER)\n' \
      "$command_label" >&2
    exit 1
  fi
}

reject_write_koios_help deploy deploy
reject_write_koios_help register register
reject_write_koios_help advance advance
reject_write_koios_help freeze freeze
reject_write_koios_help top-up top-up
reject_write_koios_help board-deploy board deploy
reject_write_koios_help board-post board post
reject_write_koios_help board-update board update
reject_write_koios_help board-retire board retire

# #351: the registry group. `registry deploy` is the one command added at the
# top: its help names every option and variable of the terms and of the node, and
# offers nothing that means a store, a manifest, a provider or cardano-cli.
"$ckeri" --help | grep -q "registry"
"$ckeri" registry --help | grep -q "deploy"
registry_deploy_help="$("$ckeri" registry deploy --help)"
for option in \
  network-magic blueprint node-socket funding-address signing-key-file \
  timeout-seconds reference-lovelace release-identity-out reference-record-out \
  registration-cost minimum-tip process-time booking-width deposit freeze-bond \
  premium minimum-ada termination-carrier; do
  grep -q -- "--$option" <<<"$registry_deploy_help"
  grep -q "CKERI_$(tr 'a-z-' 'A-Z_' <<<"$option")" <<<"$registry_deploy_help"
done
for forbidden in --store --manifest --cardano-cli CKERI_CARDANO_CLI CKERI_STORE CKERI_MANIFEST; do
  if grep -q -- "$forbidden" <<<"$registry_deploy_help"; then
    printf 'registry deploy help offers %s (#351: no store, manifest, provider or cardano-cli)\n' \
      "$forbidden" >&2
    exit 1
  fi
done
reject_retired_cardano_cli_help registry-deploy registry deploy

# An option is in a help text when both its flag and its variable are, each as a whole word:
# `--snapshot-out` and `CKERI_SNAPSHOT_OUT` do not stand for `--snapshot` and `CKERI_SNAPSHOT`.
has_option() {
  local option="$1" help
  help="$(cat)"
  grep -qE -- "--$option([^a-z-]|\$)" <<<"$help" &&
    grep -qE "CKERI_$(tr 'a-z-' 'A-Z_' <<<"$option")([^A-Z_]|\$)" <<<"$help"
}

# #351: `registry register` and `registry fold` take the files `registry deploy` wrote and the node,
# and none of the registry's terms; their help offers nothing that means a store, a manifest, a
# provider or cardano-cli.
for verb in register fold; do
  verb_help="$("$ckeri" registry "$verb" --help)"
  for option in \
    network-magic blueprint node-socket funding-address signing-key-file \
    timeout-seconds release-identity reference-record; do
    has_option "$option" <<<"$verb_help"
  done
  # register takes the controller's export; the fold takes none: the booking attested the inception
  if [[ $verb == register ]]; then
    has_option kli-export <<<"$verb_help"
  elif grep -q -- "kli-export" <<<"$verb_help"; then
    printf 'registry fold help offers kli-export (the booking attested the inception: the fold takes no export)\n' >&2
    exit 1
  fi
  for forbidden in --store --manifest --cardano-cli CKERI_CARDANO_CLI CKERI_STORE CKERI_MANIFEST --booking-width --process-time --registration-cost --premium; do
    if grep -q -- "$forbidden" <<<"$verb_help"; then
      printf 'registry %s help offers %s (#351: no store, manifest, provider, cardano-cli or registry term)\n' \
        "$verb" "$forbidden" >&2
      exit 1
    fi
  done
  reject_retired_cardano_cli_help "registry-$verb" registry "$verb"
done
registry_fold_help="$("$ckeri" registry fold --help)"
for option in request snapshot snapshot-out; do
  has_option "$option" <<<"$registry_fold_help"
done

# `registry return` is given the request by its booking output and nothing of what the request holds:
# no key export, no snapshot, no refund address, no amount.
registry_return_help="$("$ckeri" registry return --help)"
for option in \
  network-magic blueprint node-socket funding-address signing-key-file \
  timeout-seconds release-identity reference-record request; do
  has_option "$option" <<<"$registry_return_help"
done
for forbidden in --store --manifest --cardano-cli CKERI_CARDANO_CLI CKERI_STORE CKERI_MANIFEST --booking-width --process-time --registration-cost --premium --kli-export --snapshot --refund --tip --deposit; do
  if grep -q -- "$forbidden" <<<"$registry_return_help"; then
    printf 'registry return help offers %s (#351: the request holds the refund address and the amounts)\n' \
      "$forbidden" >&2
    exit 1
  fi
done
reject_retired_cardano_cli_help registry-return registry return

# #546: the four registry commands run on a node socket or on Koios (a URL and an optional token file, whose
# bytes are read by the transport): each offers the three options, and none offers a token by value.
for verb in deploy register fold return; do
  provider_help="$("$ckeri" registry "$verb" --help)"
  has_option node-socket <<<"$provider_help"
  has_option koios-url <<<"$provider_help"
  has_option koios-token-file <<<"$provider_help"
  # the network time directory is public Singular's: its option and its own variable, not a CKERI_ one; every
  # command that runs on a provider reads it, the fold included
  grep -qE -- "--network-time([^a-z-]|\$)" <<<"$provider_help"
  grep -qE "SINGULAR_NETWORK_TIME" <<<"$provider_help"
  if grep -qE -- "--koios-token([^a-z-]|\$)|CKERI_KOIOS_TOKEN([^A-Z_]|\$)" <<<"$provider_help"; then
    printf 'registry %s help offers a Koios token by value (#546: the transport reads the token from its file)\n' "$verb" >&2
    exit 1
  fi
done

# #553: the four registry commands sign with a wallet vault, the supported way, beside the key file that
# stays accepted. The descriptor is a command-line option alone: no variable of ours carries it, and the
# passphrase variable is the one `singular` has.
for verb in deploy register fold return; do
  vault_help="$("$ckeri" registry "$verb" --help)"
  has_option vault <<<"$vault_help"
  grep -qE -- "--passphrase-fd([^a-z-]|\$)" <<<"$vault_help"
  grep -q "supported way" <<<"$vault_help"
  grep -q "SINGULAR_PASSPHRASE" <<<"$vault_help"
  if grep -q "CKERI_PASSPHRASE_FD" <<<"$vault_help"; then
    printf 'registry %s help offers CKERI_PASSPHRASE_FD (#553: the descriptor is an option alone)\n' "$verb" >&2
    exit 1
  fi
done
# the installed commands refuse a missing or doubled key source by name before they read any file: every file
# they are given is a named pipe that this script holds open and keeps empty, so a command that reads one
# never ends, and `timeout` says so
unreadable="$outside/unreadable"
mkdir "$unreadable"
for name in blueprint identity record export snapshot vault key; do
  mkfifo "$unreadable/$name"
done
exec 7<>"$unreadable/blueprint" 8<>"$unreadable/identity" 9<>"$unreadable/record" 10<>"$unreadable/export" \
  11<>"$unreadable/snapshot" 12<>"$unreadable/vault" 13<>"$unreadable/key"
if timeout 2 cat "$unreadable/vault" >/dev/null 2>&1; then
  echo 'a named pipe that is held open ended a read here: the refusal checks below would prove nothing (#553)' >&2
  exit 1
fi
for verb in register fold return; do
  case "$verb" in
    fold) verb_arguments=(--request "$(printf 'a%.0s' {1..64})#0" --snapshot "$unreadable/snapshot") ;;
    register) verb_arguments=(--kli-export "$unreadable/export") ;;
    return) verb_arguments=(--request "$(printf 'a%.0s' {1..64})#0") ;;
  esac
  for key_arguments in "" "--signing-key-file $unreadable/key --vault $unreadable/vault --passphrase-fd 0"; do
    # shellcheck disable=SC2086
    refused="$(cd "$outside" && timeout 20 "$ckeri" registry "$verb" --network-magic 42 --blueprint "$unreadable/blueprint" \
      --node-socket absent.socket --funding-address addr_test1unused \
      --release-identity "$unreadable/identity" --reference-record "$unreadable/record" \
      "${verb_arguments[@]}" $key_arguments 2>&1 </dev/null || true)"
    if [[ -z "$key_arguments" ]]; then wanted="key-source-neither"; else wanted="key-source-both"; fi
    grep -q "$wanted" <<<"$refused"
    if grep -qE "unreadable" <<<"$refused"; then
      printf 'registry %s read a file before it refused the key source (#553)\n' "$verb" >&2
      exit 1
    fi
  done
done

# #546: a provider choice that is not exactly one is refused by name before any file is read: the files are
# the pipes above, held open and empty, so a command that read one would never end.
provider_wait=20
provider_expect_hang=
registry_provider_refusal() {
  local verb="$1" wanted="$2" refused status=0
  local -a verb_arguments
  shift 2
  case "$verb" in
    fold) verb_arguments=(--request "$(printf 'a%.0s' {1..64})#0" --snapshot "$unreadable/snapshot") ;;
    register) verb_arguments=(--kli-export "$unreadable/export") ;;
    return) verb_arguments=(--request "$(printf 'a%.0s' {1..64})#0") ;;
  esac
  refused="$(cd "$outside" && timeout "$provider_wait" "$ckeri" registry "$verb" --network-magic 42 --blueprint "$unreadable/blueprint" \
    --funding-address addr_test1unused --release-identity "$unreadable/identity" --reference-record "$unreadable/record" \
    --signing-key-file "$unreadable/key" "${verb_arguments[@]}" "$@" 2>&1 </dev/null)" || status=$?
  provider_status="$status"
  provider_output="$refused"
  [[ -z "$provider_expect_hang" ]] || return 0
  if [[ "$status" != 1 ]]; then
    printf 'registry %s exited %s, not 1, on a provider choice that is refused (#546; 124 is a command that read a file and waited)\n' "$verb" "$status" >&2
    exit 1
  fi
  if ! grep -q "$wanted" <<<"$refused"; then
    printf 'registry %s was not refused as %s (#546)\n' "$verb" "$wanted" >&2
    exit 1
  fi
  if grep -qE "unreadable" <<<"$refused"; then
    printf 'registry %s read a file before it refused the provider choice (#546)\n' "$verb" >&2
    exit 1
  fi
}
for verb in register return; do
  registry_provider_refusal "$verb" provider-both-given --node-socket absent.socket --koios-url http://koios.invalid/api/v1
  registry_provider_refusal "$verb" provider-none-given
  registry_provider_refusal "$verb" koios-token-file-without-koios-url --node-socket absent.socket --koios-token-file "$unreadable/key"
done
# an empty network time directory is refused by name, before any file is read
for verb in register return fold; do
  registry_provider_refusal "$verb" "needs a nonempty value" --node-socket absent.socket --network-time ""
done
registry_provider_refusal fold provider-none-given
# an exported empty network time is refused for the fold as for the other commands: it reads the network time on a provider
SINGULAR_NETWORK_TIME="" registry_provider_refusal fold "needs a nonempty value" --node-socket absent.socket
# on a provider the registry's state is rebuilt from public history: a supplied request or snapshot is refused by name before any file is read
registry_provider_refusal fold supplied-state-not-used --koios-url http://koios.invalid/api/v1
registry_provider_refusal fold provider-both-given --node-socket absent.socket --koios-url http://koios.invalid/api/v1
# the check can fail: a valid provider choice with the same pipes reads the blueprint and waits, which `timeout`
# ends with status 124, and that is what the refusals above must never do
provider_wait=3 provider_expect_hang=1 registry_provider_refusal register provider-none-given --node-socket absent.socket
if [[ "$provider_status" != 124 ]]; then
  printf 'the provider refusal check cannot tell a command that reads a file from one that refuses: status %s, not 124 (#546)\n' "$provider_status" >&2
  exit 1
fi
provider_wait=20 provider_expect_hang=

# a spelling outside the group is not a command
registry_verdict() {
  local output
  output="$("$ckeri" "$@" 2>&1 || true)"
  if sed 's/\x1b\[[0-9;]*m//g' <<<"$output" | grep -qF "Unrecognised command: ${*: -1}"; then
    echo unrecognised
  else
    echo recognised
  fi
}
[[ "$(registry_verdict registry deploy)" == recognised ]]
[[ "$(registry_verdict registry fold)" == recognised ]]
[[ "$(registry_verdict registry register)" == recognised ]]
[[ "$(registry_verdict registry return)" == recognised ]]
[[ "$(registry_verdict registry book)" == unrecognised ]]
[[ "$(registry_verdict registry-deploy)" == unrecognised ]]

"$worktree/scripts/check-deploy-register-no-cli.sh"

if rg -n \
  'Options\.Applicative|optparse-applicative' \
  offchain/cardano-keri.cabal \
  offchain/deployment \
  offchain/app; then
  echo "ckeri must use opt-env-conf exclusively" >&2
  exit 1
fi

printf '%s\n' \
  'manifest:' \
  '  verify:' \
  '    manifest: config-marker.json' \
  >"$workspace/ckeri.yaml"

expect_failure_path() {
  local expected="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    echo "expected ckeri to reject the deliberately absent $expected" >&2
    exit 1
  fi
  grep -q "$expected" <<<"$output"
}

expect_failure_path \
  "config-marker.json" \
  "$ckeri" --config-file "$workspace/ckeri.yaml" manifest verify

expect_failure_path \
  "environment-marker.json" \
  env CKERI_MANIFEST=environment-marker.json \
  "$ckeri" --config-file "$workspace/ckeri.yaml" manifest verify

expect_failure_path \
  "option-marker.json" \
  env CKERI_MANIFEST=environment-marker.json \
  "$ckeri" --config-file "$workspace/ckeri.yaml" manifest verify \
  --manifest option-marker.json

run_outside_failure() {
  local label="$1"
  shift
  local output
  local rc
  set +e
  output="$(
    cd "$outside"
    env \
      -u CKERI_CONFIG_FILE \
      -u CKERI_MANIFEST \
      -u CKERI_BOARD_MANIFEST \
      -u CKERI_BACKEND \
      -u CKERI_ENDPOINT \
      "$ckeri" "$@" 2>&1
  )"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "$label: expected ckeri to fail" >&2
    exit 1
  fi
  printf '%s\n' "$output"
}

require_contains() {
  local label="$1"
  local needle="$2"
  local output="$3"
  if ! grep -Fq -- "$needle" <<<"$output"; then
    printf '%s: expected output to contain %s; got:\n%s\n' \
      "$label" "$needle" "$output" >&2
    exit 1
  fi
}

reject_contains() {
  local label="$1"
  local needle="$2"
  local output="$3"
  if grep -Fq -- "$needle" <<<"$output"; then
    printf '%s: output must not contain %s; got:\n%s\n' \
      "$label" "$needle" "$output" >&2
    exit 1
  fi
}

require_single_line() {
  local label="$1"
  local output="$2"
  if [[ "$output" == *$'\n'* ]]; then
    printf '%s: expected one concise diagnostic line; got:\n%s\n' \
      "$label" "$output" >&2
    exit 1
  fi
}

require_named_missing() {
  local label="$1"
  local option="$2"
  local path="$3"
  local output="$4"
  require_single_line "$label" "$output"
  require_contains "$label" "ckeri:" "$output"
  require_contains "$label" "$option" "$output"
  require_contains "$label" "$path" "$output"
  require_contains "$label" "pass $option" "$output"
  reject_contains "$label" "withBinaryFile" "$output"
}

aid=EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA

board_output="$(
  run_outside_failure \
    missing-board-default \
    status \
    --aid "$aid" \
    --backend koios \
    --manifest "$worktree/deploy/preprod/m1-manifest.json"
)"
require_named_missing \
  missing-board-default \
  --board-manifest \
  deploy/preprod/board-manifest.json \
  "$board_output"

missing_manifest="$outside/missing-m1-manifest.json"
manifest_output="$(
  run_outside_failure \
    missing-explicit-manifest \
    status \
    --aid "$aid" \
    --backend koios \
    --manifest "$missing_manifest" \
    --board-manifest "$worktree/deploy/preprod/board-manifest.json"
)"
require_named_missing \
  missing-explicit-manifest \
  --manifest \
  "$missing_manifest" \
  "$manifest_output"

printf '{' >"$outside/malformed-m1-manifest.json"
malformed_manifest_output="$(
  run_outside_failure \
    malformed-manifest \
    status \
    --aid "$aid" \
    --backend koios \
    --manifest "$outside/malformed-m1-manifest.json" \
    --board-manifest "$worktree/deploy/preprod/board-manifest.json"
)"
require_single_line malformed-manifest "$malformed_manifest_output"
require_contains \
  malformed-manifest \
  "ckeri: Unexpected end-of-input, expecting record key literal or }" \
  "$malformed_manifest_output"
reject_contains malformed-manifest "pass --manifest" "$malformed_manifest_output"

printf '{' >"$outside/malformed-board-manifest.json"
malformed_board_output="$(
  run_outside_failure \
    malformed-board-manifest \
    status \
    --aid "$aid" \
    --backend koios \
    --manifest "$worktree/deploy/preprod/m1-manifest.json" \
    --board-manifest "$outside/malformed-board-manifest.json"
)"
require_single_line malformed-board-manifest "$malformed_board_output"
require_contains \
  malformed-board-manifest \
  "ckeri: Unexpected end-of-input, expecting record key literal or }" \
  "$malformed_board_output"
reject_contains malformed-board-manifest "pass --board-manifest" "$malformed_board_output"

# option, environment and configuration file reach the command in that order
registry_terms=(
  --node-socket none.socket --funding-address addr_test1none
  --signing-key-file none.skey
  --registration-cost 1 --minimum-tip 1 --process-time 1 --booking-width 1
  --deposit 1 --freeze-bond 1 --premium 1 --minimum-ada 1 --termination-carrier 1
)
printf '%s\n' \
  'registry:' \
  '  deploy:' \
  '    release-identity-out: registry-config-marker/identity.json' \
  >"$workspace/registry.yaml"
expect_failure_path \
  "registry-config-marker" \
  "$ckeri" --config-file "$workspace/registry.yaml" registry deploy "${registry_terms[@]}"
expect_failure_path \
  "registry-environment-marker" \
  env CKERI_RELEASE_IDENTITY_OUT=registry-environment-marker/identity.json \
  "$ckeri" --config-file "$workspace/registry.yaml" registry deploy "${registry_terms[@]}"
expect_failure_path \
  "registry-option-marker" \
  env CKERI_RELEASE_IDENTITY_OUT=registry-environment-marker/identity.json \
  "$ckeri" --config-file "$workspace/registry.yaml" registry deploy "${registry_terms[@]}" \
  --release-identity-out registry-option-marker/identity.json

# The packaged default blueprint is the deployed generation's, and an explicit blueprint wins over
# it, observed as the file the process opens (a registry command that loads its identity opens the
# blueprint before it reaches the node): the packaged default is the committed
# offchain/deployed-generation/plutus.json by content, not the current source build, which is of
# the attested generation the observer-era derivations refuse.
#
# Each invocation has its own trace and passes only on what its own trace records: the tracer must
# have run to the end of the traced process (a missing or empty trace is a failure, never a
# fallback to an earlier one), and the blueprint named is a file that invocation opened. The default
# invocation clears CKERI_BLUEPRINT, so a caller that already points at the deployed blueprint
# cannot stand in for the packaged default.
nixpkgs=github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46
deployed_sha="$(sha256sum "$worktree/offchain/deployed-generation/plutus.json" | cut -d' ' -f1)"
printf '{"type":"PaymentSigningKeyShelley_ed25519","description":"","cborHex":"5820%s"}\n' \
  "$(printf 'ab%.0s' $(seq 1 32))" >"$workspace/none.skey"
printf '{}\n' >"$workspace/request.json"
cp "$worktree/offchain/deployed-generation/plutus.json" "$workspace/override-plutus.json"
cp "$worktree/offchain/deployed-generation/plutus.json" "$workspace/flag-plutus.json"
return_args=(
  registry return --network-magic 1 --node-socket none.socket
  --funding-address addr_test1vqg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygxrcya6
  --signing-key-file "$workspace/none.skey"
  --release-identity "$worktree/offchain/deployment-test/fixtures/registry-v1/release-identity.json"
  --reference-record "$worktree/offchain/deployment-test/fixtures/registry-v1/reference-outputs.json"
  --request "$workspace/request.json"
)
tracer=(nix shell "$nixpkgs#strace" --command strace)
# The traced command records its own pid (a process of the tracee, not a line of the trace) and then
# becomes the command, so the pid is the command's whatever the trace says.
# The blueprint files one invocation opened to a file descriptor, from a trace of its own that
# records the exit of that command: a missing or empty trace, a trace of other processes' exits only
# (the threads and children of a traced process exit ahead of it), and an open that returned an
# error (any errno, not only ENOENT) are failures. The command's own exit status is read from its
# exit record and must be a normal exit; that it is nonzero here (the fixture record is of an earlier
# form) is not a failure.
blueprints_opened() {
  local trace command_pid
  trace="$(mktemp "$workspace/trace.XXXXXX")"
  pidfile="$(mktemp "$workspace/pid.XXXXXX")"
  "${tracer[@]}" -f -e trace=openat -o "$trace" \
    sh -c 'printf "%s\n" "$$" >"$1"; shift; exec "$@"' sh "$pidfile" "$@" >/dev/null 2>&1 || true
  command_pid="$(cat "$pidfile" 2>/dev/null || true)"
  [[ "$command_pid" =~ ^[0-9]+$ ]] || { echo "the command did not run: $*" >&2; return 1; }
  grep -aqE "^$command_pid \+\+\+ exited with [0-9]+ \+\+\+$" "$trace" \
    || { echo "the trace does not record the exit of the command ($command_pid): $*" >&2; return 1; }
  { grep -aE '^[0-9]+ openat\(.*plutus.json".*\) = [0-9]+$' "$trace" \
      | grep -o '"[^"]*plutus.json"' | tr -d '"' | sort -u; } || true
}
# One file, and it is the expected one: by path for an override, by content for the default.
only_opened() {
  local opened
  opened="$(blueprints_opened "${@:2}")" || return 1
  [[ -n "$opened" && "$(printf '%s\n' "$opened" | wc -l)" -eq 1 ]] || {
    echo "expected one blueprint opened, got: ${opened:-none}" >&2; return 1; }
  case "$1" in
    sha:*) [[ "$(sha256sum "$opened" | cut -d' ' -f1)" == "${1#sha:}" ]] ;;
    *) [[ "$opened" == "$1" ]] ;;
  esac || { echo "expected ${1}, opened $opened" >&2; return 1; }
}
# the packaged default: the caller's CKERI_BLUEPRINT cleared
only_opened "sha:$deployed_sha" env -u CKERI_BLUEPRINT "$ckeri" "${return_args[@]}" \
  || { echo "the packaged default is not the deployed generation's blueprint" >&2; exit 1; }
# the environment overrides the default
only_opened "$workspace/override-plutus.json" env CKERI_BLUEPRINT="$workspace/override-plutus.json" \
  "$ckeri" "${return_args[@]}" \
  || { echo "CKERI_BLUEPRINT did not override the packaged default" >&2; exit 1; }
# the option wins over the environment
only_opened "$workspace/flag-plutus.json" env CKERI_BLUEPRINT="$workspace/override-plutus.json" \
  "$ckeri" "${return_args[@]}" --blueprint "$workspace/flag-plutus.json" \
  || { echo "--blueprint did not win over CKERI_BLUEPRINT" >&2; exit 1; }

# Controls, each shown able to fail, after valid traces exist. A control is a tracer that does not
# produce the trace the check requires, or a file the command cannot open.
refused() { # the invocation must be refused by only_opened
  local what="$1"; shift
  if "$@" 2>/dev/null; then echo "control: $what" >&2; exit 1; fi
}
default_invocation=(env -u CKERI_BLUEPRINT "$ckeri" "${return_args[@]}")
# a wrong expectation: the default taken for the flag's file
refused "the default was taken for the flag's file" \
  only_opened "$workspace/flag-plutus.json" "${default_invocation[@]}"
# a tracer that does not trace, and one that fails
refused "a tracer that did not run passed" \
  bash -c "$(declare -f blueprints_opened only_opened); workspace='$workspace'; tracer=(true); only_opened sha:$deployed_sha \"\$@\"" _ "${default_invocation[@]}"
refused "a failed tracer passed" \
  bash -c "$(declare -f blueprints_opened only_opened); workspace='$workspace'; tracer=(false); only_opened sha:$deployed_sha \"\$@\"" _ "${default_invocation[@]}"
# a trace of thread exits only: the command ran, the trace records the exit of another process and
# the open of the expected file, but not the exit of the command
thread_exit_only_tracer() { # strace -f -e trace=openat -o FILE command...: the FILE is the fifth argument
  local out="$5"; shift 5
  "$@" >/dev/null 2>&1 || true
  printf '%s openat(AT_FDCWD, "%s", O_RDONLY) = 3\n%s +++ exited with 0 +++\n' \
    424242 "$workspace/override-plutus.json" 424242 >"$out"
}
refused "a trace of another process's exit passed" \
  bash -c "$(declare -f blueprints_opened only_opened thread_exit_only_tracer); workspace='$workspace'; tracer=(thread_exit_only_tracer); only_opened '$workspace/override-plutus.json' \"\$@\"" _ \
  env CKERI_BLUEPRINT="$workspace/override-plutus.json" "$ckeri" "${return_args[@]}"
# a failed open at the expected path, with a normal exit of the command in the trace: first a trace
# written to say so, then the real thing, a file the process may not read (EACCES, not ENOENT)
failed_open_tracer() { # the command ran; its trace records the expected open as an error
  local out="$5"; shift 5
  "$@" >/dev/null 2>&1 || true
  printf '%s openat(AT_FDCWD, "%s", O_RDONLY) = -1 EACCES (Permission denied)\n%s +++ exited with 1 +++\n' \
    "$(cat "$pidfile")" "$workspace/override-plutus.json" "$(cat "$pidfile")" >"$out"
}
refused "an open that failed with EACCES passed" \
  bash -c "$(declare -f blueprints_opened only_opened failed_open_tracer); workspace='$workspace'; tracer=(failed_open_tracer); only_opened '$workspace/override-plutus.json' \"\$@\"" _ \
  env CKERI_BLUEPRINT="$workspace/override-plutus.json" "$ckeri" "${return_args[@]}"
if [[ "$(id -u)" != 0 ]]; then
  cp "$worktree/offchain/deployed-generation/plutus.json" "$workspace/denied-plutus.json"
  chmod 000 "$workspace/denied-plutus.json"
  refused "a blueprint the process could not read passed" \
    only_opened "$workspace/denied-plutus.json" \
    env CKERI_BLUEPRINT="$workspace/denied-plutus.json" "$ckeri" "${return_args[@]}"
fi

echo "ckeri packaged default blueprint is the deployed generation's; environment and option overrides win: OK"
echo "ckeri opt-env-conf surface and option/environment/YAML precedence: OK"
echo "ckeri outside-checkout manifest diagnostics: 4/4 exercised"
