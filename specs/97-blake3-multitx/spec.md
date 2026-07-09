# Feature Specification: Checkpointed Multi-Tx BLAKE3 Spike

Issue: https://github.com/lambdasistemi/cardano-keri/issues/97

## User Story

As a cardano-keri protocol designer, I need evidence that a single BLAKE3 chunk
can be verified across chained transactions, so inception events between roughly
700 and 1024 bytes can still receive cryptographic genesis binding instead of
remaining only registration-attested.

## Background

Spike 88 and PR 96 produced an optimized single-transaction Aiken BLAKE3 core.
That core is correct against official hash-mode vectors and fits representative
inputs up to roughly 700 bytes, but a 1024-byte single chunk exceeds the
mainnet per-transaction budget. The identity model's section 7a identifies this
as the remaining trusted-base-case gap for genesis binding.

The design for this spike checkpoints the strict fold over 64-byte BLAKE3
blocks. Each transaction re-supplies the original input in the redeemer, checks
it against a small datum commitment with Plutus' native `blake2b_256`, advances
the chaining value, and either carries the checkpoint forward or finishes with
`CHUNK_END + ROOT`.

## Scope

In scope:

- A new independent spike at `spikes/97-blake3-multitx/`.
- Aiken BLAKE3 fold helpers exposing checkpoint absorb and finish behavior while
  reusing the optimized single-chunk core from spike 88 as reference material.
- A checkpoint validator with datum and redeemer shapes from issue 97.
- Aiken tests for official vectors, the 1024-byte 8+8-block split, and rejection
  paths.
- Haskell support under `offchain/` for mid-chunk chaining values and matching
  checkpoint datum/redeemer encoding.
- Measurements for Step and Finish transactions at a 1024-byte 8+8-block split,
  with a `REPORT.md` verdict against the mainnet budget.

Out of scope:

- Multi-chunk BLAKE3 tree hashing above 1024 bytes.
- Devnet submission of chained transactions.
- Edits to `spikes/88-blake3-plutus/` or `specs/68-keystate-shape/`.

## Functional Requirements

- FR-001: The spike directory MUST contain a standalone Aiken project that can be
  checked with `nix shell nixpkgs#aiken --command aiken check`.
- FR-002: The Aiken BLAKE3 module MUST expose a checkpointable fold over a single
  BLAKE3 chunk, including initial chaining value, full-block absorb, finish, and
  whole-input hash verification helpers.
- FR-003: The checkpoint datum MUST carry `input_commitment`, `cv`, `offset`,
  `len`, and `expected_digest`. `expected_digest` MUST be exactly the 32-byte
  BLAKE3 digest. KERI E-prefix identifiers carry the complete 32-byte digest, so
  a caller-selected short or oversized value MUST be rejected — accepting a short
  prefix would let a caller bind identity to a truncated digest and destroy the
  cryptographic genesis binding.
- FR-004: The checkpoint redeemer MUST support `Step` and `Finish`. `Step`
  absorbs one or more full 64-byte blocks from the supplied input and requires a
  continuing output at the same validator address, with preserved value and
  preserved `input_commitment`, `len`, and `expected_digest`. `Finish` absorbs
  the remaining segment and compares the resulting 32-byte digest with
  `expected_digest` for full equality.
- FR-005: Every Step and Finish validation MUST reject a redeemer input whose
  `blake2b_256` digest differs from the datum's `input_commitment`.
- FR-006: A Step transition MUST reject an incorrect previous chaining value,
  incorrect output offset, changed preserved datum fields, missing continuing
  output, or changed continuing value.
- FR-007: Finish MUST reject early finish attempts, wrong expected digests, and
  inconsistent offsets or lengths.
- FR-007a: Both Step and Finish MUST reject any datum whose `expected_digest` is
  not exactly 32 bytes long (shorter or longer), with attack-shaped tests that
  fail against a length-permissive implementation before the fix.
- FR-008: Aiken tests MUST cover official BLAKE3 hash vectors and the 1024-byte
  split where the first transaction absorbs 8 blocks and the finish transaction
  absorbs the remaining 8 blocks.
- FR-009: The Haskell offchain package MUST expose functions for the same
  BLAKE3 single-chunk chaining values and MUST test them against the same
  vectors, including the 1024-byte 8+8 split.
- FR-010: The Haskell offchain package MUST expose PlutusData encoders/decoders
  for the checkpoint datum and redeemer matching the Aiken constructor indices
  and field order.
- FR-011: `REPORT.md` MUST state Step and Finish ex-units for the 1024-byte 8+8
  split at TWO levels, recorded separately: (a) the core `checkpoint.step` /
  `checkpoint.finish` helpers, and (b) the full spend validator invoked through
  its script-context arguments (`spend(datum, redeemer, own_ref, tx)`), so that
  the continuing-output traversal and datum decode are counted and fixture setup
  is not mistaken for validator cost. Both levels MUST be compared to the
  14,000,000 memory and 10,000,000,000 CPU mainnet per-transaction budgets.
- FR-012: The `REPORT.md` verdict MUST follow the FULL spend-validator numbers,
  not the core-helper numbers. If the full path does not fit, the report MUST say
  so honestly rather than declaring a fit from the core helpers alone.
- FR-013: `REPORT.md` MUST record, as a caveat only, that production checkpoint
  authenticity still requires the unique state/thread-token and pinned lifecycle
  work owned by issue #99; this spike does not implement #99.

## Success Criteria

- `./gate.sh` passes locally at HEAD before the PR is marked ready.
- The branch contains one bisect-safe implementation commit per slice, with
  `Tasks: T097` trailers on behavior-changing commits.
- The PR body links the report and summarizes whether the chained design closes
  the 700-1024 byte gap within budget.
