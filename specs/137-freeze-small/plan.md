# Implementation Plan: freeze a small identity end to end (#137)

**Branch**: `story/137-freeze-small` | **Date**: 2026-07-27
**Spec**: `specs/137-freeze-small/spec.md`

## Summary

Open the Freeze arm in the small checkpoint as the same two-program pattern
that made #142 deployable: the checkpoint script owns only state mechanics and
an exact observer ran-check; a dedicated reference-delivered
`observer_enforcement` owns evidence binding and the heavy unchanged Freeze
predicate. Extend ordinary Advance to consume an ARMED wrapper before its
deadline and return to ACTIVE with the complete value.

The live story uses a deterministic keripy fixture: Register, first witnessed
rotation, then two successive pairs of conflicting rotations signed by the
keys committed at each ACTIVE tip and receipted by the same incoming
witnesses. The first pair Arms and resolves, replaying that first conflict at
the advanced state rejects, and the fresh second pair Arms and resolves again.

## Constitution and scope

- RED precedes validator and builder behavior changes.
- Existing predicates, thresholds, role tags, and deadline semantics are
  reused without redesign. ARMED response Advance adds observer action tag 3
  solely to select its datum wire; ACTIVE Advance remains tag 1.
- ClaimFreeze remains absent/fail-closed. There is no Frozen transition,
  payout, seizure, conviction, or bond release.
- Existing Register, Close, and ACTIVE Advance paths are regression gates.
- Machine facts (hashes, sizes, ex-units, txids, exits) are captured directly
  from commands and frozen logs.

## Story-shaped file surface

Expected behavior-changing surface:

```text
offchain/test/keri-fixtures/gen_fixtures.py
offchain/test/keri-fixtures/fixtures/freeze_story.json
offchain/test/keri-fixtures/fixtures/manifest.json
offchain/lib/Cardano/KERI/AID/Checkpoint/Wire.hs
offchain/test/Cardano/KERI/AID/Checkpoint/WireSpec.hs
offchain/e2e/CheckpointTxBuilder.hs
offchain/e2e/CheckpointE2ESpec.hs
offchain/flake.nix
onchain/lib/cardano_keri/checkpoint/enforcement_observer.ak
onchain/lib/cardano_keri/checkpoint/observer.ak
onchain/validators/checkpoint_observer.ak
onchain/validators/checkpoint_register.ak
onchain/validators/checkpoint_register_tests.ak
```

Minimal build metadata or recipe lines may change only if the new committed
fixture or live example is otherwise not built or executed. No tx-tools
Globals/guard work, Cage work, Claim builder, or seven-key fixture enters this
story.

## Phase 1 — keripy contested-rotation oracle

Extend the pinned fixture generator with one witnessed two-key lineage:

1. `icp` with two current keys, two committed next keys, three witnesses, and
   `toad=2`;
2. `rot_1`, revealing the inception commitment and producing the ACTIVE tip
   used on Cardano;
3. `rot_2_recorded` and `rot_2_conflict`, both at sequence two, both revealing
   the same keys committed by `rot_1`, but committing to different next keys;
4. `rot_3_recorded` and `rot_3_conflict`, both chained from
   `rot_2_recorded`, both revealing its committed keys, but committing to
   different next keys; and
5. two controller signatures and threshold witness receipts over each exact
   rotation serialization.

The generator asserts same AID, sequence, and revealed keys; different raw
bytes and next commitments; and signature/receipt verification. The committed
fixture exports offsets and signer seeds needed by the production encoders.

RED Haskell fixture/wire tests pin the contested-pair facts and the exact
Freeze spend/observer envelope shapes before production builder changes.

## Phase 2 — applied on-chain RED

Extend `checkpoint_register_tests.ak` with transaction-level tests that fail
against the current small validator:

- coupled checkpoint + enforcement observer accepts valid Freeze evidence and
  creates the exact ARMED wrapper;
- missing/wrong observer claim rejects;
- wrong-AID or uncommitted-reveal evidence rejects;
- insufficient prior controller quorum rejects;
- insufficient witness receipts reject;
- changed value, bad hunter, and wrong deadline reject;
- ARMED response Advance succeeds strictly before deadline and rejects at the
  deadline; and
- a ClaimFreeze-shaped/unknown redeemer remains fail-closed.

The pure #106 vectors are the oracle. The tests invoke both applied scripts;
they do not substitute direct pure-predicate calls for the observer boundary.

## Phase 3 — minimal on-chain GREEN

### Thin checkpoint

Add `enforcement_hash` and `freeze_window` application parameters and validate
their floors. Add:

```text
Freeze { hunter_pkh }
```

The branch:

- validates an ACTIVE/V1 named input and exact token/reserve;
- requires a zero-lovelace enforcement withdrawal whose envelope is
  `action=2`, the applied checkpoint policy, and the named input reference;
- derives `deadline` from the raw finite validity upper endpoint plus
  `freeze_window`;
- creates one ARMED-role `ArmedV1` output with exact inner datum, hunter, and
  deadline; and
- preserves complete Value and forbids own-policy mint/burn.

`ClaimFreeze` is not added.

### Enforcement observer

Add the applied `observer_enforcement` validator and action tag 2. It accepts
only Freeze, resolves the named checkpoint input to the ACTIVE/V1 datum, binds
the existing `EnforcementEvidence`, and requires `freeze_predicate` success.
It supports permissionless stake-credential registration and no
deregistration, matching the other observer families.

### ARMED response

Extend both thin and heavy Advance sides to recognize an ARMED input:

- unwrap `ArmedV1`;
- route it under response-Advance observer action tag 3 while ACTIVE Advance
  remains tag 1;
- require a finite upper endpoint strictly before its deadline;
- validate the unchanged Advance predicate against the inner checkpoint; and
- create the same unique ACTIVE successor and preserve complete Value.

The ACTIVE Advance path remains byte-for-byte equivalent in behavior.

## Phase 4 — offchain RED/GREEN and live story

Add exact wire encoders for bare Freeze and the enforcement observer envelope.
Extend `CheckpointEnv` to apply, size-check, deploy, register, and retain the
enforcement observer reference script.

Build Freeze with:

- checkpoint and enforcement reference inputs;
- the bare checkpoint `Freeze { hunter_pkh }` spending redeemer;
- zero-lovelace enforcement withdrawal and full evidence envelope;
- ARMED role output and `ArmedV1` datum;
- two-pass evaluation/budget binding so the exact final submitted bytes are
  re-evaluated; and
- observed ex-unit reporting for both scripts.

Build the response with the existing Advance two-pass machinery, using the
ARMED input and a before-deadline validity plan. The exact final bytes
evaluated equal the exact bytes submitted.

The single live story is:

```text
hash-proof -> Register -> first Advance
           -> Freeze(contested rot_2 branch)
           -> response Advance(other rot_2 branch)
           -> reject stale replay(contested rot_2 branch)
           -> Freeze(contested rot_3 branch)
           -> response Advance(other rot_3 branch)
```

It records all settled txids, the hunter/deadline, complete-value preservation,
both applied program sizes, and observed/declared ex-units. The stale replay
and the existing evidence-negative rows run at the coupled applied boundary
without submission.

## Verification and delivery

- Repin the flake-owned fixed-output Aiken blueprint after the new
  `observer_enforcement` handler and Freeze arm are compiled; the e2e runner
  must consume that exact immutable blueprint.

1. Regenerate the pinned fixture and prove drift determinism.
2. Run path-scoped Aiken formatting and focused Aiken tests.
3. Run path-scoped Fourmolu and focused Hspec/HLint before the expensive gate.
4. Report checkpoint and enforcement-observer applied program sizes against
   16,133 bytes.
5. Run the authorized stock-PV11 live story and freeze its log.
6. Run `./gate.sh` once on the final exact tree.
7. Commit one story-shaped changeset, push `story/137-freeze-small`, open a
   ready plain-body PR with `Closes #137`, settled txids, program sizes, and
   observed costs.
8. Wait for CI green, then PARK for operator merge review. Do not merge.

## Risk controls

- A script-size miss stops architecture work; no inlining or byte hunting.
- A substantive live failure is frozen before correction.
- The response validity interval is derived from the live ARMED deadline and
  current ledger tip; no wall-clock reconstruction or invented margin.
- ClaimFreeze, payout, conviction, and Frozen output symbols are explicit diff
  exclusions.
