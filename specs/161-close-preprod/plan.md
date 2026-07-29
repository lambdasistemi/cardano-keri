# Story 161 implementation plan

## Design

Extend only the deployment/application layer around the already deployed V1
Close arms:

- `Cardano.KERI.AID.Checkpoint.Wire` exposes the frozen `CloseBurn` mint
  redeemer encoding already exercised by the production E2E builder.
- `Deployment.Close` owns refund-address decoding, deterministic
  `CloseMessage` signing packages, public metadata, and controller-signature
  attachment through the shared pure Close predicate.
- `Deployment.CloseTransaction` owns the exact reference spend+burn
  `cardano-cli` plan, fee/collateral selection, submission, and settlement
  polling for both the burn and exact target refund.
- `ChainIndex` and `CheckpointIndex` add typed Koios asset-history,
  script-redeemer, and transaction-output queries so status distinguishes a
  proved Close from generic absence or conviction.
- `CLI` adds the `opt-env-conf` `close` surface and prepare/submit modes.

Reuse the frozen `CloseContext`, `CloseEvidence`,
`reconstructCloseMessage`, `canonicalCbor`, `closePredicate`, and
`closeSpendRedeemerData`. Reuse the existing registration/advance process,
wallet, Koios-token, error-rendering, and settlement conventions. Do not
change or republish Aiken.

## TDD slices

### S1 — exact Close signing package

RED pins decoding of ordinary enterprise and base Cardano addresses into the
full Aiken address wire, rejects bootstrap/wrong-network/checkpoint-script
targets, and proves the canonical-CBOR package binds target, active outref,
policy, AID, and both sequence numbers.

RED also proves no signatures or private facts enter the prepared package,
wrong/outref-stale signatures fail locally, and current controller signatures
satisfy the shared predicate.

GREEN adds the package builder, SHA-256 metadata, atomic public package files,
and the KLI-side binary signer.

### S2 — spend+burn transaction and closed status

RED pins both redeemers, exact `--tx-out`, singleton burn, shared immutable
reference, no successor datum, funding/collateral separation, and distinct
refund/change addresses.

RED gives ChainIndex realistic Koios JSON for asset history, script
redeemers, and transaction outputs. It proves Close requires the same txid's
constructor-1 mint plus constructor-0 spend, and that ConvictBurn,
registration, missing halves, or another txid never render closed status.

GREEN adds the two-purpose transaction runner, exact-refund settlement poll,
history-aware status, and the `opt-env-conf` CLI. The existing CLI checker
mechanically covers option/environment/YAML names and forbids
`optparse-applicative`.

### S3 — real validator negative and complete preprod journey

Build the packaged CLI on the preprod node host. Create a fresh 1-of-1 KLI
identity, export it, register it, prepare Close, and create an unrelated KLI
identity. Its binary signature is admitted only under the alarming
acceptance switch and must fail during real checkpoint-script evaluation.

Then sign with the true controller, settle Close, and poll the exact 1,007
tADA target output, burn history, redeemers, and closed status. Capture every
literal command and output with `script(1)` and `tee`; never retype or sanitize
the artifact.

### S4 — docs, CI evidence, final gate

Add `docs/user/close.md`, navigation/index links, a transcript/package
integrity checker, a `just` recipe, and an M1 Close GitHub Actions job that
passes optional `KOIOS_TOKEN`. Embed the exact raw transcript in the PR body.

Run the full ticket gate, strict docs build, live transcript check, and
finalization audit; push, wait until every required CI check is green, mark the
PR ready, and park it for milestone-desk audit without merging.

## Live-boundary question

Unit and devnet tests cannot prove that the five immutable reference outputs
remain live, the production node evaluates the same two-purpose Close
transaction, the full escrow reaches the named preprod target, or Koios
exposes enough history to distinguish CloseBurn from ConvictBurn.

Those facts must be crossed by the raw preprod capture and rechecked by CI.
The funded submission remains the authorized live boundary; no rejected
transaction is submitted.

## Risk controls

- Never read, print, or copy KERI seed material from `ckeri`.
- Never print or copy the Cardano payment signing key.
- Reconstruct signed bytes from the current exact ACTIVE output and target.
- Refuse outref or target drift before submission.
- Require the checkpoint input to hold only complete lovelace plus the one
  checkpoint token expected by the deployed Close arm.
- Query and name exact UTxOs; never spend the reference-script output.
- Select distinct fee and collateral UTxOs.
- Keep refund and change outputs at distinct addresses.
- Require both successful Close redeemers before status labels history closed.
- Do not modify or redeploy V1 scripts.
