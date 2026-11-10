#!/usr/bin/env bash
# The identities of the registry the devnet journey creates: the terms, and the
# application, the state script and the checkpoint validator applied to them and
# to a fixed reference seed, from the blueprint compiled from the tracked
# sources. One `label|value` row each, in the labels of the identities page;
# the first row is the compiler the blueprint records.
#
#   bash scripts/registry-identities.sh
#
# Needs nix. The program is scripts/registry-identities.hs, run in the offchain
# dev shell against the library's own derivation and the journey's own terms.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root/offchain"

blueprint=$(nix build --quiet --no-write-lock-file --no-link --print-out-paths .#plutus-blueprint)

compiler=$(sed -nE 's/^ *"version": "v([0-9.]+)\+.*"$/\1/p' "$blueprint" | head -1)
[[ -n $compiler ]] || { echo "the blueprint records no compiler version" >&2; exit 1; }
echo "Aiken compiler|$compiler"

nix develop --quiet --no-write-lock-file -c bash -c '
  set -euo pipefail
  cabal build cardano-keri cardano-keri:deployment -O0 \
    --project-file=cabal.project.devshell >&2
  cabal exec -O0 --project-file=cabal.project.devshell -- \
    runghc -ie2e ../scripts/registry-identities.hs "$1"
' _ "$blueprint"
