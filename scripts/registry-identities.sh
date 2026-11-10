#!/usr/bin/env bash
# The identities of this generation's registry scripts: the application, the
# state script and the checkpoint validator, applied to the deployed
# generation's terms and a fixed reference seed, from the blueprint compiled
# from the tracked sources. One line each: <name> <script hash> <program bytes>,
# then the registry name of the reference seed.
#
#   bash scripts/registry-identities.sh
#
# Needs nix. The program is scripts/registry-identities.hs, run in the offchain
# dev shell against the library's own derivation.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root/offchain"

blueprint=$(nix build --quiet --no-write-lock-file --no-link --print-out-paths .#plutus-blueprint)

nix develop --quiet --no-write-lock-file -c bash -c '
  set -euo pipefail
  cabal build cardano-keri cardano-keri:deployment -O0 \
    --project-file=cabal.project.devshell >&2
  cabal exec -O0 --project-file=cabal.project.devshell -- \
    runghc ../scripts/registry-identities.hs "$1"
' _ "$blueprint"
