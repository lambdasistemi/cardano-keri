#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for page in d07 d09; do
  node demo/later-model-rehearsal.mjs "$page" --fast >/dev/null
  cast="docs/demos/assets/video/${page}-checkpoint-model.cast"
  SHELL=/bin/bash DEMO_PAUSE_MS=3500 \
    nix shell github:NixOS/nixpkgs/117cc7f94e8072499b0a7aa4c52084fa4e11cc9b#asciinema \
    -c asciinema rec --overwrite --quiet --cols 80 --rows 24 \
    --env SHELL,TERM --title "Cardano KERI ${page} checkpoint model rehearsal" \
    -c "node demo/later-model-rehearsal.mjs $page" "$cast"
  node demo/validate-later-model-cast.mjs "$cast" "$page"
done
