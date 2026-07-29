#!/usr/bin/env bash
set -euo pipefail

ckeri="${1:?usage: check-ckeri-cli.sh CKERI}"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

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

echo "ckeri opt-env-conf surface and option/environment/YAML precedence: OK"
