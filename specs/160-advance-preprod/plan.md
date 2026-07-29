# Story 160 implementation plan

## Design

Extend the deployment library without changing any on-chain script:

- `KEL` gains a pure multi-message export parser and rotation projection.
- `Advance` owns signing-package construction, detailed Plutus JSON,
  `cardano-cli` argument plans, submit/settlement, and the three explicit
  acceptance-negative variants.
- `CheckpointIndex` exposes the fully validated exact ACTIVE output needed by
  both status and advance.
- `CLI` adds the `opt-env-conf` `advance` settings and selects prepare or
  submit mode.

Reuse `AdvanceEvidence`, `SpentCheckpoint`, `reconstructAdvanceMessage`,
`canonicalCbor`, `advancePredicate`, `advanceSpendRedeemerData`, and
`advanceObserverRedeemerData` from the frozen library. Reuse registration's
process/funding/Koios conventions instead of implementing a second ledger
client.

## TDD slices

### S1 — genuine multi-message KLI export

RED adds a genuine keripy 1.3.5 witnessed 2-of-5 inception→rotation export.
Tests pin framing, raw rotation bytes, all field offsets, thresholds, five
keys, witness cut/add, incoming-set derivation, native event signatures, and
two or more receipts.

GREEN generalizes message framing and adds a rotation decoder. Security-
relevant unknown CESR attachment shapes fail closed. The existing inception
fixtures and registration parser remain byte-compatible.

### S2 — exact checkpoint and signing package

RED pins conversion from the live Koios output and parsed rotation to
`SpentCheckpoint`, successor datum, canonical-CBOR preimage, package digest,
and unsigned evidence. It proves the KERI event signatures do not verify over
that preimage, while binary-safe rotated-key signatures do.

GREEN adds deterministic package files and signature ingestion. Package
metadata contains only public facts and hashes. Submit mode reconstructs and
compares rather than trusting package-supplied datum, outref, or message
fields.

### S3 — opt-env-conf surface and transaction plan

RED extends the command-surface/precedence check for every advance
option/environment/YAML spelling and mechanically forbids
`optparse-applicative`.

RED also pins the exact reference-script spend and withdrawal arguments,
unchanged full value, inline successor datum, no mint, payer/collateral
separation, transaction signing, and settlement polling.

GREEN adds the parser and runner. `cardano-cli conway transaction build` owns
balancing and live script evaluation.

### S4 — validator-boundary negatives

RED builds three applied-validator E2E cases through the same production wire:
one controller signature, one receipt, and a stale rotation against the
successor checkpoint. Each must reach the `observer-advance` script and fail;
the complete evidence must settle.

GREEN adds tightly-scoped acceptance switches that only remove otherwise-valid
evidence or permit intentional stale replay. Default mode refuses incomplete
packages locally.

### S5 — live preprod, docs, capture, CI

Build the packaged CLI and execute the complete KLI inception→register→rotate→
advance journey with the immutable manifest and public witness pool. Capture
all literal commands/output using `script(1)` and `tee`, including settled
register and advance txids and all three validator failures.

Add the rotate guide and a transcript-integrity/live-Koios CI check. Embed the
exact committed transcript in the PR body, run `./gate.sh`, push, wait for all
checks, audit metadata/worktree cleanliness, and park the ready PR for the
operator.

## Live-boundary question

Unit and local-devnet tests cannot prove the deployed reference outrefs are
unspent, public witnesses receipt the new event, the production node evaluates
the exact transaction identically, or Koios follows the successor. Those facts
must appear in the raw preprod transcript.

The issue's one-shot command also omits the deployed validator's separate
binary `AdvanceMessage` signature requirement. The explicit prepare/sign/
submit contract in the spec is pending epic-owner ratification; implementation
can proceed through the non-conflicting KEL, package, transaction, and applied-
validator layers without weakening or replacing the live validator.

## Risk controls

- Never print, export, or read KERI seed material from `ckeri`.
- Never print or copy the Cardano payment signing key.
- Reconstruct all signed facts from the current live output and KEL.
- Refuse package/outref drift before submission.
- Preserve the checkpoint's complete value and singleton asset exactly.
- Query and name exact UTxOs; never consume either reference-script output.
- Select distinct fee and collateral UTxOs.
- Submit only after build and local signature checks succeed.
- Do not modify or redeploy V1 scripts in this application story.
