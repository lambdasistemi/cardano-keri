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

- [ ] T097-F1 Update the draft PR body with delivered behavior, report link, and verification evidence.
- [ ] T097-F2 Rerun `./gate.sh` at HEAD and record the result.
- [ ] T097-F3 Run the finalization audit for this PR and this task file.
- [ ] T097-F4 Drop `gate.sh` in `chore: drop gate.sh (ready for review)`.
- [ ] T097-F5 Mark the PR ready only after local gate and CI are green.
