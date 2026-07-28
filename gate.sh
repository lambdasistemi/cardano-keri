#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
git diff --check
just ci

nix develop github:paolino/dev-assets?dir=mkdocs --quiet \
  -c mkdocs build --strict --site-dir site

nix run nixpkgs#lychee -- \
  --no-progress \
  --include-fragments \
  --user-agent "Mozilla/5.0 (X11; Linux x86_64) cardano-keri-linkcheck" \
  --max-retries 3 \
  docs
