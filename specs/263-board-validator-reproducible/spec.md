# Feature specification — #263 reproducible endpoint-board validator

Artifact ceiling: 6,000 bytes and 150 lines.

## Outcome

The repository owns the exact 3,158-byte endpoint-board validator deployed at
policy `54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c`, proves that
identity from bytes, and uses that artifact in the deployment and local
write-path proofs which were intentionally deferred by #240.

## Resolution evidence

The recovery path is selected; redeployment is unnecessary. A clean rebuild of
source commit `95b554fbdc9dee5b4437d3a8deeb882f114a0bf3` with its historical Nix
closure and Aiken 1.1.21 reproduced:

- full blueprint SHA-256
  `896d2c4642740a26248dc46cdeecbce18730061785e78cfbedc2a13a5c9c577c`;
- validator title `endpoint_board.endpoint_board.mint`;
- 3,158 program bytes with SHA-256
  `b9562988d5d1c8995a0e58a4ebbec21848352f8b1e9e363b46dc3b36bd8543fe`;
- the frozen deployed policy above.

## Requirements

- **RQ-263-01 — repository artifact:** a checked-in preproduction board
  artifact contains the exact recovered program bytes and records its title,
  byte length, program digest, source commit, historical compiler, and source
  blueprint digest.
- **RQ-263-02 — distinct binding:** deployment and local-write-path tests load
  that board artifact through a board-specific path. The current checkpoint
  blueprint remains independently source-built and is not treated as the
  deployed board artifact.
- **RQ-263-03 — derived identity:** an executing permanent check decodes the
  repository artifact through the production blueprint/board derivation path
  and asserts its exact byte length, digest, and frozen policy ID.
- **RQ-263-04 — falsifiable check:** perturbing one compiled-program nibble
  makes the permanent identity check RED; restoring it makes the same check
  GREEN. The negative-control receipt is retained outside the repository.
- **RQ-263-05 — manifest proof:** the pending endpoint-board manifest test is
  unparked and executes the exact frozen-artifact derivation and equality.
- **RQ-263-06 — board verb proofs:** #240's endpoint-board post, update, and
  retire residual cases become complete local read-set/build proofs seeded
  with the recovered reference script.
- **RQ-263-07 — no weakening:** production `consumerErrors` remains an exact
  equality check against the frozen policy and unchanged by the behavior
  commit.
- **RQ-263-08 — retained boundaries:** no provider fallback, remote read, or
  live-chain action is introduced; existing #240/#262 local routing and
  snapshot invariants remain green.

## Invariants

- **INV-263-REPRODUCIBLE (BLOCKING):** repository-owned bytes have length
  3,158, program digest `b9562988...43fe`, and derive policy
  `54494f8a...1210c`. A byte perturbation must make the permanent check RED.
- **INV-263-ASSERTED (BLOCKING):** the ticket gate executes the production
  `deriveBoardScript` path over the repository artifact and compares the
  result with the frozen manifest identity.
- **INV-263-UNPARKED (BLOCKING):** no pending/disabled manifest equality case
  remains; the test executes and passes with the recovered artifact.
- **INV-263-NO-WEAKENING (BLOCKING):** `consumerErrors` retains exact policy
  equality and no bypass, alternate accepted identity, or warning-only path is
  added.

## Rejection behavior

- Missing, malformed, wrongly titled, wrongly sized, digest-mismatched, or
  policy-mismatched artifacts fail closed before a board deployment/build
  proof can pass.
- The board-specific artifact path never falls back to the current source
  blueprint or a provider.

## Non-goals

- No preproduction or mainnet transaction is built, signed, submitted, or
  deployed.
- The deployed policy is not changed and no new policy is approved.
- The Aiken source is not rewritten merely to reproduce historical compiler
  output; its current blueprint remains the checkpoint/source-build input.
