#!/usr/bin/env bash
# #181 Slices 2-4 — the complete deployment path, including live CLI
# composition, owns no subprocess/cardano-cli path or retired runner
# configuration.
#
# Proves itself able to fail before it is trusted to pass the real source:
# a positive-control fixture deliberately contains a forbidden cardano-cli
# shell-out, and the guard is rejected as broken if it does not detect it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$repo_root/scripts/fixtures/deploy-register-cardano-cli-positive-control.hs.txt"
publisher="$repo_root/offchain/deployment/Cardano/KERI/Deployment/Publisher.hs"
registration="$repo_root/offchain/deployment/Cardano/KERI/Deployment/Registration.hs"
advance="$repo_root/offchain/deployment/Cardano/KERI/Deployment/AdvanceTransaction.hs"
close="$repo_root/offchain/deployment/Cardano/KERI/Deployment/CloseTransaction.hs"
board="$repo_root/offchain/deployment/Cardano/KERI/Deployment/EndpointBoardTransaction.hs"
cli="$repo_root/offchain/deployment/Cardano/KERI/Deployment/CLI.hs"

subprocess_pattern='System\.Process|readProcessWithExitCode|callProcess|createProcess|cardano-cli'

if ! grep -qE "$subprocess_pattern" "$fixture"; then
  echo "deploy-register-no-cli-guard: positive-control fixture ($fixture) does not contain a forbidden subprocess reference; the guard cannot prove itself able to fail" >&2
  exit 1
fi
echo "deploy-register-no-cli-guard: positive control OK (guard detects $fixture)"

# This closes both the visible query and transaction-build-in-disguise paths.
modules=("$publisher" "$registration" "$advance" "$close" "$board" "$cli")
violations="$(grep -nE "$subprocess_pattern" "${modules[@]}" || true)"
if [ -n "$violations" ]; then
  echo "deploy-register-no-cli-guard: a migrated transaction module still contains a subprocess path:" >&2
  echo "$violations" >&2
  exit 1
fi

retired_fields=(
  publishCardanoCli
  runnerCardanoCli
  closeRunnerCardanoCli
  boardRunnerCardanoCli
  AdvanceRunnerConfig
  CloseRunnerConfig
  BoardRunnerConfig
  deployCardanoCli
  registerCardanoCli
  advanceCardanoCli
  closeCardanoCli
  boardTransactionCardanoCli
)
for field in "${retired_fields[@]}"; do
  survivors="$(grep -nF -- "$field" "${modules[@]}" || true)"
  if [ -n "$survivors" ]; then
    echo "deploy-register-no-cli-guard: retired deploy/register cardano-cli field survives ($field):" >&2
    echo "$survivors" >&2
    exit 1
  fi
done

if grep -nF 'pending #181 Slice 4 composition' "$cli"; then
  echo "deploy-register-no-cli-guard: a Slice 4 fail-closed tail survives" >&2
  exit 1
fi

echo "deploy-register-no-cli-guard: OK — no subprocess path, retired runner surface, or Slice 4 stop in deployment composition"
