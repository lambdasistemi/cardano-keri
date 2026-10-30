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
