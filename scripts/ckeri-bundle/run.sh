#!/usr/bin/env bash
# Stranger entry point: assemble the declared inventory and run every
# bundle check. Depends only on this checkout and its declared pins.
set -euo pipefail

bundle_dir=$(cd "$(dirname "$0")" && pwd)
dest=${1:-}

if [ -z "$dest" ]; then
  dest=$(mktemp -d "${TMPDIR:-/tmp}/ckeri-bundle.XXXXXXXX")
fi
mkdir -p "$dest"

"$bundle_dir/assemble.sh" \
  "$bundle_dir/inventory.txt" \
  "$bundle_dir" \
  "$dest"

"$bundle_dir/check-completeness.sh" \
  "$bundle_dir/inventory.txt" \
  "$dest"

"$bundle_dir/check-claim-schema.sh" \
  "$dest/claims/schema-fixture.txt"

"$bundle_dir/check-published-bytes.sh" \
  "$dest/fixtures/clean-identity.json"

[ -s "$dest/COVERAGE-BOUNDARY.md" ] \
  || { echo "coverage boundary prose missing from assembled bundle" >&2; exit 1; }

echo "CKERI-BUNDLE-RUN dest=$dest entry_point=scripts/ckeri-bundle/run.sh exit=0"
