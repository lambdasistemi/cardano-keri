#!/usr/bin/env bash
# Reproducible keripy fixture regeneration for #106.
#
# keripy is not in nixpkgs, so this directory carries its own flake (flake.nix
# + pinned uv.lock) that builds keripy 1.3.5 hermetically via uv2nix. keripy is
# therefore available in a nix shell WITHOUT any network `pip`/`uv install`:
#
#   nix develop            # shell with keripy + libsodium (SODIUM_LIB set)
#   nix run .#gen          # regenerate the committed fixtures in ./fixtures
#
# This wrapper pins the output directory to the committed fixtures path and
# runs the generator through the flake's dev shell, so `bash run.sh` from
# anywhere regenerates the same bytes. The gate's opt-in drift check
# (CARDANO_KERI_KERI_FIXTURES=1) calls this and requires no git diff.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FIXTURES_OUT="$HERE/fixtures"

nix develop "$HERE" --command python "$HERE/gen_fixtures.py"
