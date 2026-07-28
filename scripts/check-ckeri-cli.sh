#!/usr/bin/env bash
set -euo pipefail

ckeri="${1:?usage: check-ckeri-cli.sh CKERI}"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

"$ckeri" --help | grep -q "deploy"
"$ckeri" --help | grep -q "manifest"
"$ckeri" deploy --help | grep -q -- "--node-socket"
"$ckeri" deploy --help | grep -q "CKERI_NODE_SOCKET"
"$ckeri" manifest verify --help | grep -q -- "--manifest"
"$ckeri" manifest verify --help | grep -q "CKERI_MANIFEST"

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
