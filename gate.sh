#!/usr/bin/env bash
# PR-life mechanical gate for #115 (advance path). Dropped before mark-ready.
set -euo pipefail
cd "$(dirname "$0")"

git diff --check

# Full CI aggregate (root justfile; each recipe enters its own flake — no
# nix develop wrapper here). Mirrors .github/workflows/ci.yml:
#   ci-onchain: format-check-onchain check-onchain measure-enforcement
#               measure-hash-proof measure-checkpoint
#   ci-blake3:  compiler-check-blake3 format-check-blake3 check-blake3
#   ci-offchain: build-offchain unit hlint format-check-offchain
#                devshell-offchain check-checkpoint-vectors
#                check-enforcement-vectors check-registration-vectors
just ci
