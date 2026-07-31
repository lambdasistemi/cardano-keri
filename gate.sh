#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
git diff --check
just ci
just ci-live
