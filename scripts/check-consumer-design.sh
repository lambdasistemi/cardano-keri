#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Fresh model output, all sampled theorem properties, generic CLI parity and
# source/story bindings. The full Lean trust inventory is a separate gate.
node simulator/consumer-gate.mjs
node simulator/checkpoint-simulator-build.mjs --check
consumer_mutation_receipts=$(mktemp -d)
trap 'rm -rf -- "$consumer_mutation_receipts"' EXIT
node simulator/consumer-js-mutants.mjs "$consumer_mutation_receipts"
# Concrete consumer identity bytes (#489): the committed vectors are the Lean's
# output, every committed row and field is checked against the consumer
# predicate, and Singular's independent preimage table at the pinned revision
# is reproduced byte for byte.
(
  cd lean
  lake build CardanoKeri.ConsumerBytesVectors
  lake env lean --run ConsumerBytesDriver.lean | diff -u consumer-identity-vectors.json -
  lake env lean --run ConsumerBytesDriver.lean --check consumer-identity-vectors.json
  lake env lean --run ConsumerBytesDriver.lean --singular \
    .lake/packages/singular/offchain/test/fixtures/preimage-vectors.json
)
