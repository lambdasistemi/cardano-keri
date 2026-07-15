#!/usr/bin/env bash
set -euo pipefail
# gate.sh — mechanical PR gate for cardano-keri #68
# (design(identity): freeze weighted CheckpointDatumV1 and CBOR boundary).
#
# Present in the branch for the PR's whole life; dropped in the final
# `chore: drop gate.sh (ready for review)` commit before mark-ready. Its
# presence at HEAD is the "PR in flight" sentinel; its absence means finalized.
#
# Every reviewed slice must pass this before the ticket owner accepts + pushes.
# The gate is extended per-slice (accept.sh staged targets, executable golden /
# negative / parity checks) in dedicated `chore: extend gate.sh with <name>`
# commits.

cd "$(dirname "$0")"

# 1. No whitespace errors / leftover conflict markers in the diff. STRICT.
git diff --check

# 2. Ticket-specific acceptance contract — the #68 wire-contract gate.
#    specs/68-keystate-shape/accept.sh is authored RED-first and exposes staged
#    per-slice targets plus the default `final` verdict. It is FAIL-SAFE (absent
#    artifacts are RED, never a crash), so a clean checkout that predates the
#    planning artifacts simply skips this block and still runs strict CI (step 3).
#
#      - `spec`  — Layer-1 structural self-check of the frozen wire-contract
#        record. GREEN at planning HEAD, so it is enforced STRICTLY here: any
#        regression in the spec's well-formedness fails the whole gate immediately.
#
#      - `final` — the whole deliverable contract (datum + threshold + message
#        domains + byte-identical Aiken/Haskell golden & negative vectors +
#        reconciled canonical docs). It is *legitimately* RED until the schema /
#        vector / doc slices land. We RUN it and REPORT its verdict every time (so
#        progress stays visible) but TOLERATE a RED `final` while the PR is in
#        flight (gate.sh present at HEAD = pre-final-slice). The tolerance is
#        bounded to `final` ONLY — never to `spec`, `git diff --check`, or CI.
#
#    Each later slice makes this block ENFORCE its own staged target STRICTLY by
#    extending it in a dedicated `chore: extend gate.sh with <name>` commit. The
#    final slice REMOVES the `final` tolerance below (calls `accept.sh final`
#    strictly) — the last gate change before `chore: drop gate.sh (ready for
#    review)`.
if [ -x specs/68-keystate-shape/accept.sh ]; then
  # spec (Layer-1 structural) — STRICT: a non-zero exit fails the gate.
  specs/68-keystate-shape/accept.sh spec

  # final (whole contract) — RUN + REPORT; RED tolerated pre-final-slice (see above).
  if specs/68-keystate-shape/accept.sh final; then
    echo "gate.sh: accept.sh final GREEN"
  else
    echo "gate.sh: accept.sh final RED (tolerated — PR in flight, pre-final-slice;" \
         "the final-slice extension removes this tolerance and makes final strict)"
  fi
fi

# 3. Repo CI (mirrors .github/workflows/ci.yml): onchain + BLAKE3 + offchain. STRICT.
#    Root `just ci` is the aggregate source of truth and is invoked as plain
#    `just ci` (NOT `nix develop -c just ci`): this repository has no root flake,
#    and each aggregated recipe already enters its OWN correct Nix flake/shell
#    context — ci-onchain (aiken shell), ci-blake3 (pinned spike flake), and
#    ci-offchain's packaged build + unit + hlint + format-check PLUS the
#    `devshell-offchain` dev-shell build (offchain flake).
#    #68's executable deliverables live inside this gate: the schema-support codec
#    slices add Aiken `onchain/lib` tests (covered by `aiken check`) and Haskell
#    hspec suites + a golden/negative/parity vector drift check (covered by the
#    offchain unit target), so this strict `./gate.sh` actually runs them.
just ci
