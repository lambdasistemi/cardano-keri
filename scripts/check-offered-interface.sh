#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
node specs/400-offered-interface/check-conformance.mjs
node specs/400-offered-interface/check-statements.mjs
node scripts/generate-offered-reference.mjs
python3 tools/check_presentation.py --no-speech \
  --front specs/400-offered-interface/spec.md specs/400-offered-interface
python3 tools/check_presentation.py --no-speech \
  --front docs/offered-api/index.md docs/offered-api/*.md
