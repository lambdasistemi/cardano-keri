# Tasks: Checkpointed Multi-Tx BLAKE3 Spike

Issue task trailer for behavior-changing commits: `Tasks: T097`

## Bootstrap

- [X] T097-B1 Add `./gate.sh` as the first branch commit.
- [X] T097-B2 Open a draft PR for `feat/97-blake3-multitx`, labeled `feat` and assigned to `paolino`.
- [X] T097-B3 Commit and push this spec, plan, and task breakdown before dispatching implementation slices.

## Slice 1 - Aiken Checkpoint Core

Owned files:

- `spikes/97-blake3-multitx/aiken.toml`
- `spikes/97-blake3-multitx/aiken.lock`
- `spikes/97-blake3-multitx/README.md`
- `spikes/97-blake3-multitx/lib/blake3.ak`
- `spikes/97-blake3-multitx/lib/blake3_tests.ak`

Tasks:

- [X] T097-S1 Create the standalone spike Aiken project without editing spike 88.
- [X] T097-S1 Refactor the optimized BLAKE3 core into checkpointable absorb and finish helpers.
- [X] T097-S1 Add RED-first Aiken tests for official vectors and the 1024-byte 8+8 split.
- [X] T097-S1 Run the focused spike command and `./gate.sh`.
- [X] T097-S1 Commit as `feat(spike): add checkpointed blake3 core`.

Focused command:

```sh
cd spikes/97-blake3-multitx && nix shell nixpkgs#aiken --command aiken check
```

## Slice 2 - Aiken Checkpoint Validator

Owned files:

- `spikes/97-blake3-multitx/lib/blake3.ak`
- `spikes/97-blake3-multitx/lib/blake3_tests.ak`
- `spikes/97-blake3-multitx/validators/checkpoint.ak`
- `spikes/97-blake3-multitx/validators/checkpoint_tests.ak`

Tasks:

- [X] T097-S2 Add datum and redeemer types matching the issue shape.
- [X] T097-S2 Add the checkpoint spend validator and pure transition helpers.
- [X] T097-S2 Add RED-first tests for accepted Step/Finish and all required rejections.
- [X] T097-S2 Run the focused spike command and `./gate.sh`.
- [X] T097-S2 Commit as `feat(spike): add blake3 checkpoint validator`.

Focused command:

```sh
cd spikes/97-blake3-multitx && nix shell nixpkgs#aiken --command aiken check
```

## Slice 3 - Haskell Chaining and Encoding

Owned files:

- `offchain/cardano-keri.cabal`
- `offchain/lib/Cardano/KERI/AID/Blake3/Checkpoint.hs`
- `offchain/test/Cardano/KERI/AID/Blake3/CheckpointSpec.hs`
- `offchain/test/Main.hs`

Tasks:

- [X] T097-S3 Add pure Haskell single-chunk BLAKE3 chaining-value support.
- [X] T097-S3 Add checkpoint datum/redeemer PlutusData encoders matching Aiken.
- [X] T097-S3 Add RED-first tests for vectors, the 1024-byte split, and PlutusData roundtrips.
- [X] T097-S3 Run focused Haskell tests and `./gate.sh`.
- [X] T097-S3 Commit as `feat(offchain): add blake3 checkpoint support`.

Focused command:

```sh
just unit "Blake3 checkpoint"
```

## Slice 4 - Measurements and Report

Owned files:

- `spikes/97-blake3-multitx/validators/measurements.ak`
- `spikes/97-blake3-multitx/REPORT.md`

Tasks:

- [X] T097-S4 Add measurement tests for Step and Finish at the 1024-byte 8+8 split.
- [X] T097-S4 Run `aiken check --plain-numbers` and record Step/Finish ex-units.
- [X] T097-S4 Compare each measurement to 14,000,000 memory and 10,000,000,000 CPU.
- [X] T097-S4 Write `REPORT.md` with the fit/no-fit verdict and follow-up notes.
- [X] T097-S4 Run `./gate.sh`.
- [X] T097-S4 Commit as `docs(spike): report blake3 multitx measurements`.

Focused command:

```sh
cd spikes/97-blake3-multitx && nix shell nixpkgs#aiken --command aiken check --plain-numbers
```

## Finalization

- [X] T097-F1 Update the draft PR body with delivered behavior, report link, and verification evidence.
- [X] T097-F2 Rerun `./gate.sh` at HEAD and record the result.
- [X] T097-F3 Run the finalization audit for this PR and this task file.
- [X] T097-F4 Drop `gate.sh` in `chore: drop gate.sh (ready for review)`.
- [X] T097-F5 Mark the PR ready only after local gate and CI are green.

## Remediation (reopened after parent review)

Two acceptance gaps found in parent review. Landed as focused bisect-safe commits
on top (history-fold not safely practical: no interactive rebase, fixes span three
published + independently-verified commits). See plan.md "Remediation".

### Slice R1 - Require the full 32-byte checkpoint digest

Owned files:

- `spikes/97-blake3-multitx/validators/checkpoint.ak`
- `spikes/97-blake3-multitx/validators/checkpoint_tests.ak`
- `spikes/97-blake3-multitx/validators/measurements.ak`
- `offchain/lib/Cardano/KERI/AID/Blake3/Checkpoint.hs`
- `offchain/test/Cardano/KERI/AID/Blake3/CheckpointSpec.hs`

Tasks:

- [X] T097-R1 Rename `expected_prefix` -> `expected_digest` across Aiken and Haskell (positional PlutusData unchanged).
- [X] T097-R1 Pin `expected_digest` length to exactly 32 bytes in `shape_is_valid`; reduce comparison to full equality.
- [X] T097-R1 Add RED-first attack tests: Step and Finish reject short (8, 31) and oversized (33) digests.
- [X] T097-R1 Update every short-prefix fixture to a real 32-byte digest; drop `finish_accepts_partial_prefix`.
- [X] T097-R1 Update Haskell golden/roundtrip fixtures to 32-byte digests and the renamed field.
- [X] T097-R1 Run the focused spike + Haskell commands and `./gate.sh`.
- [X] T097-R1 Commit as `fix(spike): require full 32-byte checkpoint digest`.

Focused commands:

```sh
cd spikes/97-blake3-multitx && nix shell nixpkgs#aiken --command aiken check
just unit "Blake3 checkpoint"
```

### Slice R2 - Full spend-validator context measurements

Owned files:

- `spikes/97-blake3-multitx/validators/measurements.ak`
- `spikes/97-blake3-multitx/REPORT.md`

Tasks:

- [X] T097-R2 Add full-context measurement tests calling `checkpoint.spend(..)` for Step and Finish with literal `const` fixtures.
- [X] T097-R2 Run `aiken check --plain-numbers` and record core AND full-context ex-units separately.
- [X] T097-R2 Rewrite `REPORT.md`: separate core/full numbers, compare full path to budget, verdict follows full evidence.
- [X] T097-R2 Add the issue #99 authenticity caveat (state/thread-token + pinned lifecycle) as a caveat only.
- [X] T097-R2 Run `./gate.sh`.
- [X] T097-R2 Commit as `docs(spike): measure full spend-validator context`.

Focused command:

```sh
cd spikes/97-blake3-multitx && nix shell nixpkgs#aiken --command aiken check --plain-numbers
```

### Slice R3 - Orchestrator re-finalization

- [ ] T097-R3 Restore `gate.sh` for the reopened PR life (done at reopen).
- [ ] T097-R3 Update the PR body with corrected evidence and full-context numbers.
- [ ] T097-R3 Rerun `./gate.sh` and `just ci` at HEAD and record results.
- [ ] T097-R3 Run the finalization audit for this PR and this task file.
- [ ] T097-R3 Drop `gate.sh` in `chore: drop gate.sh (ready for review)`.
- [ ] T097-R3 Mark the PR ready only after local gate and CI are green; leave merge to the parent.
