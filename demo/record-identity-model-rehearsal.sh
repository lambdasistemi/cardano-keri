#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
node demo/identity-model-rehearsal.mjs --fast >/dev/null
cast=docs/demos/assets/video/d04-d06-identity-model.cast
mkdir -p "$(dirname "$cast")"
SHELL=/bin/bash DEMO_PAUSE_MS=3500 \
  nix shell github:NixOS/nixpkgs/117cc7f94e8072499b0a7aa4c52084fa4e11cc9b#asciinema \
  -c asciinema rec --overwrite --quiet --cols 80 --rows 24 \
  --env SHELL,TERM --title 'Cardano KERI D-04 to D-06 model rehearsal' \
  -c 'node demo/identity-model-rehearsal.mjs' "$cast"
node demo/validate-identity-model-cast.mjs "$cast"
