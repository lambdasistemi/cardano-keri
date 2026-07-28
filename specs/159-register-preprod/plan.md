# Story 159 implementation plan

## Design

Keep `ckeri` as one packaged executable and extend its public deployment
library with three application modules:

- `KEL` is pure: frame the inception event, decode compact JSON, counters and
  indexed Ed25519 signatures, derive offsets/datum/evidence, and reject trailing
  or unsupported first-message shapes.
- `Registration` is the `cardano-cli` boundary: derive script-data JSON and
  transaction arguments, query funding/collateral, run build/sign/submit, and
  poll Koios for settlement.
- `CheckpointIndex` is the Koios exact-asset boundary used by both duplicate
  preflight and `status`.

Reuse the frozen types and encoders from the main `cardano-keri` library.
Reference-script hashes/outrefs and addresses come only from the committed
manifest plus the same applied-script derivation used by deploy/verify. Shelling
out to the packaged `cardano-cli` follows story 158 and avoids a second
transaction implementation.

## TDD slices

### S1 — real `kli export` parser

RED adds deployment tests containing genuine keripy 1.3.5 exports for
unwitnessed 1-of-1 and witnessed 2-of-5 inception. Tests require:

- exact event framing from `KERI10JSON......_`;
- current/next thresholds and all five keys;
- all three witnesses and `toad = 2`;
- five controller indexed signatures and three witness receipts;
- E1-E9 offsets that reproduce the raw fields; and
- the existing pure registration predicate to accept the result.

GREEN implements only the CESR 1.0 material emitted by the pinned CLI:
`-V` attachment group, `-A` controller group, `-B` witness group, 88-character
small Ed25519 indexed signatures, and ignorable first-seen replay material.
Unknown security-relevant attachment shapes fail closed.

### S2 — opt-env-conf surface and preflights

RED extends the command-surface check for `register` and `status`, every
option/environment/YAML spelling, the optional Koios bearer token, and the
absence of `Options.Applicative`.

GREEN adds settings and runners. Pure tests cover network rejection,
witness-default refusal/acknowledgement, exact-asset zero/one/many decisions,
already-registered refusal before any transaction command is run, and the
explicit sovereign repeat-registration acknowledgement.

### S3 — reference-script transaction runner

RED tests exact `cardano-cli` argument plans and detailed script-data JSON:
hash-proof mint, proof burn/checkpoint mint, lifecycle withdrawal, inline V1
datum, reference outrefs, collateral, protected output value, and payment-key
signing.

GREEN implements temporary-file materialization and process execution.
`cardano-cli conway transaction build` owns protocol parameters, balancing and
script evaluation. The runner extracts signed txids, submits unchanged signed
transactions, and waits for exact output settlement. Failure output retains
the Plutus evaluation diagnostic while never exposing signing-key content.

### S4 — exact-asset status

RED uses a local HTTP server to cover anonymous/token-authenticated Koios
requests and zero/one/ambiguous/malformed responses. It pins ACTIVE V1 rendering
for 1-of-1 and 2-of-5.

GREEN queries the Koios asset UTxO endpoint, validates role address, token,
inline datum, AID, and escrow, then renders the stable one-line status.

### S5 — live boundary, docs, and capture

Build the packaged CLI and run the full journey against the production preprod
socket and immutable manifest. Use stock keripy 1.3.5 and the three public
witness OOBIs. Ensure the payer has enough preprod funds for two 1007 tADA
escrows plus fees before submission.

Capture via `script(1)` with a wrapper that prints literal `$` commands before
execution, and `tee` the raw result to the committed acceptance artifact.
Exercise:

1. clean 1-of-1 inception/export/register/status;
2. clean witnessed 2-of-5 inception/export;
3. default witness-policy refusal and explicit acknowledgement;
4. settled 2-of-5 register/status;
5. already-registered off-chain refusal;
6. explicitly acknowledged repeat registration with settled txids; and
7. one-lovelace-underfunded Plutus evaluation rejection using a fresh KEL.

Add the user guide and a CI transcript/parser check. Embed the exact committed
capture in the PR body, run `./gate.sh`, push, wait for CI, perform the
finalization audit, remove the mechanical story gate only if the repository
workflow calls for it, and park PR #172 for operator merge.

## Live-boundary question

The unit suite cannot prove:

- the production node accepts the exact reference-script transaction shape;
- live Plutus V3 evaluation agrees with local wire plans;
- Koios follows the newly settled outputs; or
- keripy’s public witnesses return the receipts carried by its export.

The raw settled preprod transcript is therefore a required operator-owned
artifact before draft removal. CI covers only deterministic framing, command
plans, configuration precedence, and transcript integrity.

## Risk controls

- Never print or copy the payment signing key.
- Query and name exact UTxOs; do not consume a reference-script output.
- Select distinct fee and collateral UTxOs.
- Submit only after `transaction build` succeeds.
- Treat Koios as discovery, then verify every output fact needed for status.
- Fail closed on multiple checkpoint outputs.
- Do not change an on-chain validator in this application story.
- Preserve #114 repeat-registration semantics and disclose the off-chain
  default/refusal boundary.
