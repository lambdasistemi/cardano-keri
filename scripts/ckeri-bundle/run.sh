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

published=$dest/published/manifest.json
toy=$dest/fixtures/clean-identity.json
if [ ! -f "$published" ]; then
  echo "published identity artifact missing: $published" >&2
  exit 1
fi
pub_digest=$(sha256sum "$published" | cut -d ' ' -f 1)
toy_digest=$(sha256sum "$toy" | cut -d ' ' -f 1)
if [ "$pub_digest" = "$toy_digest" ]; then
  echo "artifact-binding verdict is over the toy fixture, not published identity bytes" >&2
  exit 1
fi
"$bundle_dir/check-published-bytes.sh" "$published"

[ -s "$dest/COVERAGE-BOUNDARY.md" ] \
  || { echo "coverage boundary prose missing from assembled bundle" >&2; exit 1; }

echo "CKERI-BUNDLE-RUN dest=$dest entry_point=scripts/ckeri-bundle/run.sh exit=0"
