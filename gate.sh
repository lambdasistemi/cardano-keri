#!/usr/bin/env bash
set -euo pipefail
# gate.sh — mechanical PR gate for cardano-keri #92
# (design(onchain): checkpoint contention model — per-AID UTxO vs MPFS trie).
#
# Present in the branch for the PR's whole life; dropped in the final
# `chore: drop gate.sh (ready for review)` commit before mark-ready. Its
# presence at HEAD is the "PR in flight" sentinel; its absence means finalized.
#
# Every reviewed slice must pass this before the ticket owner accepts + pushes.
# The gate is extended per-slice (accept.sh, any measurement/live-boundary
# smoke) in dedicated `chore: extend gate.sh with <name>` commits.

cd "$(dirname "$0")"

# 1. No whitespace errors / leftover conflict markers in the diff.
git diff --check

# 2. Ticket-specific decision-acceptance check (added by the decision slice).
#    RED on the pre-decision tree, GREEN once the decision record lands.
if [ -x specs/92-checkpoint-contention/accept.sh ]; then
  specs/92-checkpoint-contention/accept.sh
fi

# 3. Repo CI (mirrors .github/workflows/ci.yml): onchain + BLAKE3 + offchain.
#    A pure decision-record slice touches only specs/ + docs/; any measurement
#    or prototype slice adds Aiken/Haskell that this same gate then covers.
nix develop --quiet -c just ci
