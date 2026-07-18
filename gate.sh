#!/usr/bin/env bash
# PR-life mechanical gate for #114 (registration path). Dropped before mark-ready.
set -euo pipefail
cd "$(dirname "$0")"

git diff --check

# Full CI aggregate (root justfile; each recipe enters its own flake — no
# nix develop wrapper here). Mirrors .github/workflows/ci.yml:
#   ci-onchain: format-check-onchain check-onchain measure-enforcement
#   ci-blake3:  compiler-check-blake3 format-check-blake3 check-blake3
#   ci-offchain: build-offchain unit hlint format-check-offchain
#                devshell-offchain check-checkpoint-vectors check-enforcement-vectors
just ci

# Ticket-specific proofs are appended per slice (chore: extend gate.sh ...):
# - S1+: keri-fixtures byte-stability (regen == committed; existing bundles unchanged)
# - S3+: just check-registration-vectors (drift check for the shared vector set)
