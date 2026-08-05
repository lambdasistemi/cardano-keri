#!/usr/bin/env bash
# #181 Slice 2 — deploy/register in-process transaction path: Publisher.hs
# and Registration.hs own no subprocess/cardano-cli transaction path, and
# their retired internal runner fields. CLI parsing remains intentionally
# unchanged until #181 Slice 4; only the register command's use is fenced.
#
# Proves itself able to fail before it is trusted to pass the real source:
# a positive-control fixture deliberately contains a forbidden cardano-cli
# shell-out, and the guard is rejected as broken if it does not detect it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$repo_root/scripts/fixtures/deploy-register-cardano-cli-positive-control.hs.txt"
publisher="$repo_root/offchain/deployment/Cardano/KERI/Deployment/Publisher.hs"
registration="$repo_root/offchain/deployment/Cardano/KERI/Deployment/Registration.hs"

subprocess_pattern='System\.Process|readProcessWithExitCode|callProcess|createProcess|cardano-cli'

if ! grep -qE "$subprocess_pattern" "$fixture"; then
  echo "deploy-register-no-cli-guard: positive-control fixture ($fixture) does not contain a forbidden subprocess reference; the guard cannot prove itself able to fail" >&2
  exit 1
fi
echo "deploy-register-no-cli-guard: positive control OK (guard detects $fixture)"

# This closes both the visible query and transaction-build-in-disguise paths.
# CLI.hs legitimately keeps System.Process/cardano-cli for advance/close/
# board (Slice 3 territory) so it is never scanned for this regex.
violations="$(grep -nE "$subprocess_pattern" "$publisher" "$registration" || true)"
if [ -n "$violations" ]; then
  echo "deploy-register-no-cli-guard: Publisher/Registration still contain a subprocess transaction path:" >&2
  echo "$violations" >&2
  exit 1
fi

retired_fields=(
  publishCardanoCli
  runnerCardanoCli
)
for field in "${retired_fields[@]}"; do
  survivors="$(grep -nF -- "$field" "$publisher" "$registration" || true)"
  if [ -n "$survivors" ]; then
    echo "deploy-register-no-cli-guard: retired deploy/register cardano-cli field survives ($field):" >&2
    echo "$survivors" >&2
    exit 1
  fi
done

echo "deploy-register-no-cli-guard: OK — no subprocess path or retired runner field in Publisher/Registration"
