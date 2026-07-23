#!/usr/bin/env bash
# PR-life mechanical gate for #117 (close + consumer resolution). Dropped before ready.
set -euo pipefail
cd "$(dirname "$0")"

git diff --check

# Full repository aggregate; mirrors the CI workflow through the root justfile.
just ci
