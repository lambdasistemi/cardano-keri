#!/usr/bin/env bash
set -euo pipefail

# PR-life mechanical gate for issue #99 (cage token + AID-ownership invariants).
# Removed in the final `chore: drop gate.sh` commit before mark-ready.

git diff --check

# Full CI gate: onchain (aiken fmt --check + aiken check, incl. cage tests and
# measurement tests) and offchain (build + unit + hlint + format-check + the
# upgraded dev-shell build `nix develop -c cabal build all --enable-tests -O0`,
# via `just devshell-offchain`).
just ci

# Live-boundary smoke (#99 FR9/AC9): withDevnet cage Phase-2 `Modify` settlement
# on a real cardano-node. The flake-owned `checks.x86_64-linux.e2e` runCommand
# invokes the repo-owned E2E app (getExe) with cardano-node + E2E_GENESIS_DIR as
# runtimeInputs; it submits a hardened #99 Modify and asserts it settles on-chain.
# Linux-only. Kept installed through S9b and final verification.
just e2e
