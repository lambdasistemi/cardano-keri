# Implementation Plan: convict-small (#151)

**Branch**: `story/151-convict-small` | **Date**: 2026-07-28
**Spec**: `specs/151-convict-small/spec.md`

## Summary

Open only the Convict command in the deployable small checkpoint and isolated
enforcement observer. The checkpoint owns exact source-role classification,
token burn, and payouts. The observer binds the same named input to the
existing witnessed-conflict predicate.

The ratified terminal rule is a burn: the settled transaction is the
tombstone record and no TOMBSTONE UTxO survives. ACTIVE, ARMED, and FROZEN
remain three independent proof rows because `B` is routed differently in each.

This behavior-changing story runs as a driver/navigator pair. The complete RED
package is frozen and approved before GREEN. GREEN plus the live-devnet
evidence is frozen and approved before the full gate.

## Constitution and scope

- RED precedes every on-chain and wire behavior change.
- Open only `Convict` and its exact burn/observer support.
- Preserve mint indices 0–1, spend indices 0–3, and observer actions 0–3.
- Keep the near-limit Advance observer source and applied bytes unchanged.
- Do not create or retain a TOMBSTONE output.
- Use only the pinned keripy generator for the witnessed conflicting event.
- Machine facts come from captured logs and hashes, never retyped assertions.
- The story PR includes its user-facing conviction page in the same diff.

## Expected story-shaped surface

```text
specs/151-convict-small/spec.md
specs/151-convict-small/plan.md
specs/151-convict-small/checklists/requirements.md
onchain/validators/checkpoint_register.ak
onchain/validators/checkpoint_register_tests.ak
onchain/lib/cardano_keri/checkpoint/observer.ak
onchain/lib/cardano_keri/checkpoint/enforcement_observer.ak
offchain/lib/Cardano/KERI/AID/Checkpoint/Wire.hs
offchain/test/Cardano/KERI/AID/Checkpoint/WireSpec.hs
offchain/e2e/CheckpointTxBuilder.hs
offchain/e2e/CheckpointE2ESpec.hs
offchain/flake.nix
docs/user/conviction.md
docs/architecture/lifecycle-and-bonds.md
docs/story-ladder.md
mkdocs.yml
```

`offchain/flake.nix` changes only if the immutable production blueprint hash
must be repinned after the Aiken change. No Advance-observer source change is
permitted.

## Phase 1 — complete RED package

Add applied Aiken tests that describe the absent behavior:

1. ACTIVE Convict succeeds only with exact `min + D_reg + B` convictor payout
   and an exact token burn;
2. ARMED Convict succeeds only with distinct exact `min + D_reg` convictor and
   exact `B` recorded-hunter payouts;
3. FROZEN Convict succeeds only with exact `min + D_reg` convictor payout and
   no second bond;
4. each row creates no checkpoint successor and no token-bearing output;
5. an unwitnessed conflicting event rejects; and
6. the generated recorded event rejects because it is not a conflict.

Add Haskell wire tests pinning:

- `ConvictBurn { checkpoint_ref }` at mint constructor 2;
- `Convict { convictor_pkh, convictor_output_index, hunter_output_index }` at
  spend constructor 4; and
- the enforcement envelope at action 4.

Run focused Aiken and Haskell commands against unchanged production, capture
their expected missing-API failures, freeze the entire RED diff sequentially,
and wait for a literal navigator `REVIEW-APPROVED`.

## Phase 2 — minimal on-chain and wire GREEN

In `checkpoint_register.ak`:

- add `ConvictBurn` and `Convict` only at the frozen indices;
- classify the named input as ACTIVE/direct-V1, ARMED/well-formed-ArmedV1, or
  FROZEN/direct-V1;
- derive the AID token from the inner checkpoint;
- require exactly one input token, mint exactly `-1`, and forbid that token in
  all outputs;
- require action-4 enforcement coupling for the same policy and outref;
- require each source's minimum protected reserve and exact one-token asset
  shape while allowing surplus lovelace to remain ordinary transaction change;
- enforce indexed, datum-free, lovelace-only payouts with ARMED indices
  distinct; and
- create no continuing checkpoint output.

In the enforcement observer:

- add action 4 without renumbering;
- resolve the inner checkpoint from all three admitted source shapes;
- bind `EnforcementEvidence` to the AID; and
- require `convict_predicate == ConvictValid`.

In the Haskell wire module, add the three exact encoders and no unrelated
wire changes.

## Phase 3 — generated fixture and production-shaped live proof

Run `offchain/test/keri-fixtures/run.sh` through the repository's pinned
environment and require no committed fixture drift.

Reuse its witnessed fork in three independent stock-PV11 scenarios:

1. register and advance to the recorded tip, then Convict from ACTIVE;
2. register and advance, Freeze with a later genuine conflict, then Convict
   from ARMED using the witnessed conflict at the recorded tip;
3. register and advance, Freeze, wait, ClaimFreeze into FROZEN, then Convict
   using the witnessed conflict at the recorded tip.

Before the successful ACTIVE conviction, evaluate two candidates through the
real reference scripts:

- the same conflict with witness receipts removed; and
- the generated recorded event itself, which has no conflict with the tip.

Both must reject before submission. Every successful Convict uses two-pass
evaluation, binds the exact budgets, submits the unchanged transaction, waits
for settlement, and queries the ledger to prove the source-specific payouts,
burned-token absence, and lack of a checkpoint successor.

If practical without widening production scope, re-register the same AID
under the same checkpoint policy after the ACTIVE burn and observe the new
ACTIVE checkpoint. At minimum, the on-chain and docs contract must preserve
that admissibility by creating no global tombstone barrier.

## Phase 4 — user documentation

Add `docs/user/conviction.md` and expose it in `mkdocs.yml`. The page explains:

- lag versus equivocation and why `B` differs from `D_reg`;
- fully witnessed conflict evidence;
- the atomic evidence-record, token burn, and payouts;
- exact ACTIVE, ARMED, and FROZEN value rows;
- why no TOMBSTONE UTxO survives; and
- how re-registration creates a fresh ACTIVE checkpoint after conviction.

Update the lifecycle page and story ladder only where their older
surviving-TOMBSTONE or pre-#138 wording would contradict the new user page.
Build with strict MkDocs.

## Verification and delivery

1. Run path-scoped Aiken formatting and the focused Convict tests.
2. Run Fourmolu and focused wire tests.
3. Prove pinned keripy regeneration is drift-free.
4. Repin the flake-owned Aiken blueprint hash if required.
5. Report applied checkpoint, enforcement-observer, and unchanged
   Advance-observer sizes against 16,133 bytes.
6. Run the three stock-PV11 source rows and freeze txids, payouts, costs,
   token-absence queries, and rejection logs.
7. Freeze GREEN plus live evidence sequentially and wait for the navigator's
   complete `REVIEW-APPROVED`.
8. Run `./gate.sh` once on the approved exact tree.
9. Commit one story-shaped changeset with `Closes #151`, push, and open a ready
   human-readable PR containing live txids, sizes, costs, fixture provenance,
   and docs.
10. Wait for CI green, then PARK for operator merge. Do not merge.

## Risk controls

- A payout row is not inferred from conservation; the live runner queries and
  reports the exact indexed outputs.
- ARMED's hunter index must differ from the convictor index even when both
  payment keys happen to be equal.
- FROZEN never reconstructs `B`; its exact input and payout exclude it.
- Exact asset-shape and protocol-payout checks prevent hidden assets while
  leaving lovelace above the protected reserve as ordinary change.
- The mint arm and spend arm both name the same checkpoint outref.
- An observer or checkpoint size miss stops implementation; the Advance
  observer is not edited to buy headroom.
- No GREEN edit starts before the RED verdict file is read, and no gate starts
  before the GREEN-plus-live verdict file is read.
