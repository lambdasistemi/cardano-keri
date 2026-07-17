#!/usr/bin/env bash
set -euo pipefail
# gate.sh — mechanical PR gate for cardano-keri #106
# (feat(identity): convict/freeze divergence-enforcement spend paths).
#
# Present in the branch for the PR's whole life; dropped in the final
# `chore: drop gate.sh (ready for review)` commit before mark-ready. Its
# presence at HEAD is the "PR in flight" sentinel; its absence means finalized.
#
# Every reviewed slice must pass this before the ticket owner accepts + pushes.
# The gate is extended per-slice (accept.sh staged targets, any measurement /
# live-boundary smoke) in dedicated `chore: extend gate.sh with <name>` commits.

cd "$(dirname "$0")"

# 1. No whitespace errors / leftover conflict markers in the diff. STRICT.
git diff --check

# 2. Ticket-specific acceptance contract — T9201 gate lifecycle.
#    specs/92-checkpoint-contention/accept.sh is authored RED-first and exposes
#    staged per-slice targets plus the default `final` verdict. It is FAIL-SAFE
#    (absent artifacts are RED, never a crash), so the presence guard below means
#    a clean checkout that predates the planning artifacts simply skips this block
#    and still runs strict CI (step 3).
#
#      - `spec`  — Layer-1 structural self-check of the planning record. GREEN at
#        planning HEAD, so it is enforced STRICTLY here: any regression in the
#        spec's well-formedness fails the whole gate immediately.
#
#      - `final` — the whole deliverable contract. It is *legitimately* RED until
#        Slice 9 lands the thresholds / evidence / live-smoke / DECISION +
#        canonical-doc artifacts. We RUN it and REPORT its verdict every time (so
#        its progress stays visible), but we TOLERATE a RED `final` while the PR
#        is in flight (gate.sh present at HEAD = pre-Slice-9). The tolerance is
#        bounded to `final` ONLY — never to `spec`, `git diff --check`, or CI.
#
#    Each later slice (Slices 1..8) makes this block ENFORCE its own staged target
#    STRICTLY by extending it in a dedicated `chore: extend gate.sh with <name>`
#    commit — schema, thresholds, registration, candidate-A, candidate-B,
#    candidate-C, contention, smoke — each adding a strict line for the target
#    that slice turns GREEN. Slice 9 REMOVES the `final` tolerance below (deletes
#    the `if/else`, calling `accept.sh final` strictly) so a RED `final` fails the
#    gate — the last gate change before `chore: drop gate.sh (ready for review)`.
if [ -x specs/92-checkpoint-contention/accept.sh ]; then
  # spec (Layer-1 structural) — STRICT: a non-zero exit fails the gate.
  specs/92-checkpoint-contention/accept.sh spec

  # final (whole contract) — RUN + REPORT; RED tolerated pre-Slice-9 (see above).
  if specs/92-checkpoint-contention/accept.sh final; then
    echo "gate.sh: accept.sh final GREEN"
  else
    echo "gate.sh: accept.sh final RED (tolerated — PR in flight, pre-Slice-9;" \
         "Slice 9 removes this tolerance and makes final strict)"
  fi
fi

# 2b. keripy fixture drift (#106) — OPT-IN, network-dependent.
#     The committed fixtures under specs/106-enforcement/fixtures/ are the
#     durable oracle output the Haskell/Aiken suites consume. Regenerating them
#     needs a keripy install (uv, network), so this drift check is NOT in the
#     offline path — it runs only when CARDANO_KERI_KERI_FIXTURES=1 is set
#     (CI job or manual). When enabled: regenerate and require no git diff.
if [ "${CARDANO_KERI_KERI_FIXTURES:-0}" = "1" ]; then
  bash specs/106-enforcement/run.sh
  git diff --exit-code specs/106-enforcement/fixtures/
  echo "gate.sh: keripy fixture drift check GREEN"
fi

# 3. Repo CI (mirrors .github/workflows/ci.yml): onchain + BLAKE3 + offchain. STRICT.
#    Root `just ci` is the aggregate source of truth and is invoked as plain
#    `just ci` (NOT `nix develop -c just ci`): this repository has no root flake,
#    and each aggregated recipe already enters its OWN correct Nix flake/shell
#    context — ci-onchain (aiken shell), ci-blake3 (pinned spike flake), and
#    ci-offchain's packaged build + unit + hlint + format-check PLUS the
#    `devshell-offchain` dev-shell build (offchain flake). The dev-shell build is
#    NOT orthogonal and is NOT skipped: `just ci` includes `devshell-offchain`,
#    so this strict `./gate.sh` proof actually runs it.
#    A pure planning/decision slice touches only specs/ + docs/; any measurement
#    or prototype slice adds Aiken/Haskell that this same gate then covers.
just ci
