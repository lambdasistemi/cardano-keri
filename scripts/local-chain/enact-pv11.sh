#!/usr/bin/env bash
# usage: enact-pv11.sh <node socket>
# Moves a local devnet node to protocol version 11 with the governance helper of cardano-node-clients, the
# way this repository's end-to-end journeys do. Run it inside the development shell (`nix develop` in offchain/)
# and inside the node environment of the rehearsal (the working directory is the cardano-node-clients source,
# whose fixtures the helper reads). Test code: no network, local chain only.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec cabal exec -O0 --project-dir="$here/../../offchain" --project-file=cabal.project.devshell -- runghc \
    --ghc-arg=-package=cardano-node-clients --ghc-arg=-package=async "$here/EnactPV11.hs" "$1"
