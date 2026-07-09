# Implementation Plan: Checkpointed Multi-Tx BLAKE3 Spike

## Technical Shape

The spike uses a new standalone Aiken project under
`spikes/97-blake3-multitx/`. It may copy and refactor the optimized core from
`spikes/88-blake3-plutus/lib/blake3.ak`, but spike 88 remains read-only.

The Aiken checkpoint API should keep the on-chain datum compact:

- `cv`: 32-byte chaining value in a single canonical wire representation agreed
  with Haskell.
- `offset`: number of input bytes already absorbed.
- `len`: committed input length, capped to one BLAKE3 chunk.
- `input_commitment`: `blake2b_256(input)` checked against the redeemer input.
- `expected_prefix`: digest prefix to compare at finish time.

For 1024 bytes, the target measurement path is:

1. Step transaction: absorb blocks 0-7 from offset 0, producing offset 512 and
   an advanced `cv`.
2. Finish transaction: starting at offset 512, absorb blocks 8-14 as normal
   chunk blocks and block 15 with `CHUNK_END + ROOT`, then compare the digest
   prefix.

The Haskell implementation belongs in `offchain/` because issue 97 explicitly
names `offchain/` and the existing package already owns PlutusData type mirrors.
Avoid new dependencies unless a driver proves they are already available and
materially reduce risk; a small pure `Word32` compression implementation is the
default.

## Gate

`./gate.sh` is the PR-life gate. It should run:

- `git diff --check`
- the repo's existing CI-equivalent checks via `just ci`
- the spike-local Aiken format/check commands once `spikes/97-blake3-multitx/`
  exists

Slice briefs may also name focused commands for fast RED/GREEN feedback, but a
driver must run `./gate.sh` before committing.

## Slices

### Slice 1: Aiken Checkpoint Core

Create the spike Aiken project and refactor the optimized BLAKE3 core into
checkpointable helpers. Tests should prove whole-input vectors still pass and
that absorbing 8 blocks then finishing the remaining 8 blocks for 1024 bytes
matches the official vector.

Commit subject: `feat(spike): add checkpointed blake3 core`

### Slice 2: Aiken Checkpoint Validator

Add the checkpoint datum/redeemer and spend validator. Tests should cover
accepted Step and Finish transitions plus rejection cases for wrong input
commitment, wrong chaining value or offset, early finish, wrong digest prefix,
missing continuation, changed datum fields, and changed value.

Commit subject: `feat(spike): add blake3 checkpoint validator`

### Slice 3: Haskell Chaining and Encoding

Add the offchain BLAKE3 checkpoint module, expose it from the cabal file, and
test it against the same vectors. Add PlutusData types and roundtrip/constructor
tests for the checkpoint datum and redeemer.

Commit subject: `feat(offchain): add blake3 checkpoint support`

### Slice 4: Measurements and Report

Add Aiken measurement tests for the 1024-byte 8+8 Step/Finish path, run the
measurement command with plain numbers, and write `REPORT.md` with the verdict
against mainnet memory and CPU budgets.

Commit subject: `docs(spike): report blake3 multitx measurements`

### Slice 5: Orchestrator Finalization

Update the PR body, rerun the gate, run the finalization audit, drop `gate.sh`,
mark the PR ready only after local gate and CI are green, and leave merge to the
parent.
