#!/usr/bin/env bash
# PR-life mechanical gate for reopened #115 (permissionless advance).
# Dropped before mark-ready.
set -euo pipefail
cd "$(dirname "$0")"

git diff --check

# Full repository aggregate; mirrors the CI workflow through the root justfile.
just ci
