#!/usr/bin/env bash
# usage: inspect-tx.sh <file holding a transaction's CBOR as hex>...
# Prints what a transaction pays and declares: size, fee, inputs, reference inputs, collateral, outputs,
# redeemer units, the assets it mints and burns, the treasury donation and the validity interval.
# Run it inside the development shell (`nix develop` in offchain/).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in "$@"; do
    echo "## $f"
    cabal exec -O0 --project-dir="$here/../../offchain" --project-file=cabal.project.devshell -- runghc \
        --ghc-arg=-package=cardano-node-clients --ghc-arg=-package=cardano-ledger-binary "$here/TxInspect.hs" "$f"
done
