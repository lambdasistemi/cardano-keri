#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
git diff --check
just ci

if rg -q '^executable[[:space:]]+ckeri$' offchain/cardano-keri.cabal; then
  nix build --quiet ./offchain#ckeri
fi

if rg -n \
  '(^|[[:space:],])optparse-applicative($|[[:space:]<>=,])|Options\.Applicative' \
  offchain \
  --glob '*.cabal' \
  --glob '*.hs'; then
  echo "ckeri must use opt-env-conf; optparse-applicative is forbidden" >&2
  exit 1
fi

if test -f deploy/preprod/m1-manifest.json; then
  nix shell \
    nixpkgs#bash \
    nixpkgs#coreutils \
    nixpkgs#gnugrep \
    nixpkgs#jq \
    --command bash scripts/check-m1-acceptance-transcript.sh

  nix run --quiet ./offchain#ckeri -- \
    manifest verify \
    --manifest deploy/preprod/m1-manifest.json
fi

nix develop github:paolino/dev-assets?dir=mkdocs --quiet \
  -c mkdocs build --strict --site-dir site

nix run nixpkgs#lychee -- \
  --no-progress \
  --include-fragments \
  --user-agent "Mozilla/5.0 (X11; Linux x86_64) cardano-keri-linkcheck" \
  --max-retries 3 \
  docs
