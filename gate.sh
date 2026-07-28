#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
git diff --check

docker build \
  --tag cardano-keri-witness:gate \
  --file deploy/preprod/Dockerfile \
  .
WITNESS_IMAGE=cardano-keri-witness:gate \
  ./scripts/check-preprod-witnesses.sh

nix develop github:paolino/dev-assets?dir=mkdocs --quiet \
  -c mkdocs build --strict --site-dir site

nix run nixpkgs#lychee -- \
  --no-progress \
  --include-fragments \
  --accept 200,202,429 \
  --user-agent "Mozilla/5.0 (X11; Linux x86_64) cardano-keri-linkcheck" \
  --max-retries 3 \
  docs

just ci
