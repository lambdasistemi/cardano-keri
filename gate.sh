#!/usr/bin/env bash
set -euo pipefail

git diff --check

just ci

if [ -d spikes/97-blake3-multitx ]; then
  (
    cd spikes/97-blake3-multitx
    nix shell nixpkgs#aiken --command aiken fmt --check
    nix shell nixpkgs#aiken --command aiken check --plain-numbers
  )
fi
