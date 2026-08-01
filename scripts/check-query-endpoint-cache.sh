#!/usr/bin/env bash
# #176 Slice 1 — FR-4 static guard: the query HTTP layer owns no mutable
# derived state (no IORef/MVar/TVar allocation, no unsafePerformIO).
#
# Proves itself able to fail before it is trusted to pass the real source:
# a positive-control fixture deliberately contains a forbidden primitive,
# and the guard is rejected as broken if it does not detect it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$repo_root/scripts/fixtures/cache-guard-positive-control.hs.txt"
scan_targets=(
  "$repo_root/offchain/indexer/Cardano/KERI/Indexer/Query"
  "$repo_root/offchain/indexer/Cardano/KERI/Indexer/Board.hs"
)

forbidden='newIORef|newMVar|newTVar|newTVarIO|unsafePerformIO'

if ! grep -qE "$forbidden" "$fixture"; then
  echo "cache-guard: positive-control fixture ($fixture) does not contain a forbidden primitive; the guard cannot prove itself able to fail" >&2
  exit 1
fi
echo "cache-guard: positive control OK (guard detects $fixture)"

violations="$(grep -rEn "$forbidden" "${scan_targets[@]}" || true)"
if [ -n "$violations" ]; then
  echo "cache-guard: forbidden mutable-state primitive found in the query layer (FR-4 violation):" >&2
  echo "$violations" >&2
  exit 1
fi

echo "cache-guard: OK — no mutable derived state in ${scan_targets[*]}"
