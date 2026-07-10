#!/usr/bin/env bash
set -euo pipefail

# PR-life mechanical gate for issue #99 (cage token + AID-ownership invariants).
# Removed in the final `chore: drop gate.sh` commit before mark-ready.

git diff --check

# Full CI gate: onchain (aiken fmt --check + aiken check, incl. cage tests and
# measurement tests) and offchain (build + unit + hlint + format-check + devshell).
just ci
