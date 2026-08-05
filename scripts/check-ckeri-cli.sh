#!/usr/bin/env bash
set -euo pipefail

ckeri="$(realpath -- "${1:?usage: check-ckeri-cli.sh CKERI}")"
worktree="$(pwd -P)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
outside="$workspace/outside-checkout"
mkdir "$outside"

"$ckeri" --help | grep -q "deploy"
"$ckeri" --help | grep -q "manifest"
"$ckeri" --help | grep -q "register"
"$ckeri" --help | grep -q "advance"
"$ckeri" --help | grep -q "close"
"$ckeri" --help | grep -q "status"
"$ckeri" deploy --help | grep -q -- "--node-socket"
"$ckeri" deploy --help | grep -q "CKERI_NODE_SOCKET"
"$ckeri" deploy --help | grep -q -- "--koios-token"
"$ckeri" deploy --help | grep -q "KOIOS_TOKEN"
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
"$ckeri" register --help | grep -q -- "--koios-token"
"$ckeri" register --help | grep -q "KOIOS_TOKEN"
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
"$ckeri" advance --help | grep -q -- "--koios-token"
"$ckeri" advance --help | grep -q "KOIOS_TOKEN"
"$ckeri" advance --help | grep -q "validator-test-under-signed"
"$ckeri" advance --help | grep -q "validator-test-under-witnessed"
"$ckeri" advance --help | grep -q "validator-test-stale"
"$ckeri" close --help | grep -q -- "--aid"
"$ckeri" close --help | grep -q "CKERI_AID"
"$ckeri" close --help | grep -q -- "--kel"
"$ckeri" close --help | grep -q "CKERI_KEL"
"$ckeri" close --help | grep -q -- "--to"
"$ckeri" close --help | grep -q "CKERI_TO"
"$ckeri" close --help | grep -q -- "--signing-package"
"$ckeri" close --help | grep -q "CKERI_SIGNING_PACKAGE"
"$ckeri" close --help | grep -q -- "--controller-signatures"
"$ckeri" close --help | grep -q "CKERI_CONTROLLER_SIGNATURES"
"$ckeri" close --help | grep -q -- "--change-address"
"$ckeri" close --help | grep -q "CKERI_CHANGE_ADDRESS"
"$ckeri" close --help | grep -q -- "--koios-token"
"$ckeri" close --help | grep -q "KOIOS_TOKEN"
"$ckeri" close --help | grep -q "validator-test-non-controller"
"$ckeri" status --help | grep -q "AID"
"$ckeri" status --help | grep -q "CKERI_AID"
"$ckeri" status --help | grep -q -- "--koios-token"
"$ckeri" status --help | grep -q "KOIOS_TOKEN"
"$ckeri" status --help | grep -q -- "--board-manifest"
"$ckeri" status --help | grep -q "CKERI_BOARD_MANIFEST"
"$ckeri" board post --help | grep -q "default: 4000000"

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

echo "ckeri opt-env-conf surface and option/environment/YAML precedence: OK"
echo "ckeri outside-checkout manifest diagnostics: 4/4 exercised"
