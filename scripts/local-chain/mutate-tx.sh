#!/usr/bin/env bash
# usage: mutate-tx.sh <hex file of a settled transaction> <output hex file>   (prints the mutant's transaction id)
# See MutateTx.hs. Run inside the development shell (`nix develop` in offchain/).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec cabal exec -O0 --project-dir="$here/../../offchain" --project-file=cabal.project.devshell -- runghc \
    --ghc-arg=-package=cardano-node-clients --ghc-arg=-package=cardano-ledger-binary "$here/MutateTx.hs" "$1" "$2"
