# Implementation Plan: seize-delay (#138)

**Branch**: `story/138-seize-delay` | **Date**: 2026-07-28
**Spec**: `specs/138-seize-delay/spec.md`

## Summary

Carve the already-ratified timeout-claim mechanics into the deployable small
checkpoint validator. `ClaimFreeze` is deliberately thin: it validates the
ARMED role/datum, deadline, exact hunter payout, exact FROZEN successor value,
token continuity, and no own-policy mint. It does not use an observer.

Thaw is not a new arm. The existing `Advance` constructor and action-1
observer admit a FROZEN plain-`V1` input; only the thin checkpoint requires the
ACTIVE successor to equal the input value plus `B`. This leaves the
16,130-byte applied Advance observer untouched.

The story also establishes the standing documentation rule by shipping a
navigable user page for the complete freeze lifecycle.

## Constitution and scope

- RED precedes every validator and wire behavior change.
- Open only `ClaimFreeze`; do not add Convict, Reap, CloseIntent, or any other
  spend constructor.
- Keep `Close=0`, `Advance=1`, and `Freeze=2`; add `ClaimFreeze=3`.
- Reuse action 1 for ACTIVE and FROZEN Advance, action 3 for ARMED response.
- Preserve the unchanged heavy Advance and enforcement predicates.
- Machine facts come from command output and frozen logs.
- The PR includes the story's user documentation in the same diff.

## Expected story-shaped surface

```text
specs/138-seize-delay/spec.md
specs/138-seize-delay/plan.md
specs/138-seize-delay/checklists/requirements.md
onchain/validators/checkpoint_register.ak
onchain/validators/checkpoint_register_tests.ak
offchain/lib/Cardano/KERI/AID/Checkpoint/Wire.hs
offchain/test/Cardano/KERI/AID/Checkpoint/WireSpec.hs
offchain/e2e/CheckpointTxBuilder.hs
offchain/e2e/CheckpointE2ESpec.hs
offchain/flake.nix
docs/user/freeze-lifecycle.md
mkdocs.yml
```

`offchain/flake.nix` changes only if the immutable production blueprint hash
must be repinned after the Aiken change. No fixture regeneration or observer
source change is expected.

## Phase 1 — RED

Add applied Aiken tests that invoke the small checkpoint validator:

1. valid post-deadline ClaimFreeze succeeds;
2. early ClaimFreeze rejects;
3. a payout to the wrong hunter rejects;
4. any payout other than exactly `B` rejects;
5. the FROZEN successor is the unchanged datum/token and input value minus
   exactly `B`; and
6. a FROZEN ordinary Advance succeeds only with an ACTIVE successor equal to
   input value plus exactly `B`.

Add a Haskell wire test pinning `ClaimFreeze { hunter_output_index }` at
constructor index 3.

Run both focused suites against the unchanged implementation and freeze the
expected failures before GREEN.

## Phase 2 — minimal on-chain and wire GREEN

In `checkpoint_register.ak`:

- import the FROZEN role and hunter verification-key address constructor;
- add `ClaimFreeze { hunter_output_index: Int }`;
- dispatch it directly to `validate_claim`;
- require finite `lower >= deadline`;
- require the indexed hunter output to be datum-free, lovelace-only, exactly
  `B`, and addressed to the recorded hunter;
- require one FROZEN successor with the unchanged `V1` datum and exact
  input-minus-`B` value; and
- extend `validate_advance` so FROZEN expects exact input-plus-`B`, while
  ACTIVE equality and ARMED response equality remain unchanged.

In the Haskell wire module, add only the index-3 ClaimFreeze encoder.

## Phase 3 — production-shaped live builder

Reuse the committed #137 freeze fixture:

1. production hash-proof Register;
2. genuine witnessed first Advance;
3. genuine Freeze into ARMED;
4. evaluate an early correct-hunter claim and require phase-2 rejection;
5. poll the node until the stored deadline;
6. evaluate a post-deadline wrong-hunter claim and require phase-2 rejection;
7. two-pass evaluate, bind budgets, submit unchanged, and settle ClaimFreeze;
8. assert the hunter received exactly `B` and FROZEN retained
   `min + D_reg`; and
9. two-pass evaluate and settle the genuine sibling rotation as a thaw,
   asserting ACTIVE and exact input-plus-`B`.

The modern builder uses the checkpoint reference script. Claim has one
spending purpose and no observer. Thaw has the existing spending plus
Advance-observer purposes. The validity plans are node-derived; no wall-clock
deadline is reconstructed.

## Phase 4 — user documentation

Add `docs/user/freeze-lifecycle.md` and expose it in `mkdocs.yml`. The page is
written for checkpoint users rather than validator implementers and covers:

- why a challenge immediately fail-closes without paying;
- before-deadline response and bond retention;
- post-deadline exact hunter payout;
- FROZEN reserve and consumer behavior;
- permissionless thaw with a newly posted bond; and
- the wrong-hunter and early-claim protections.

Build with the repository's strict MkDocs command.

## Verification and delivery

1. Run path-scoped Aiken formatting and focused #138 Aiken tests.
2. Run Fourmolu and focused Haskell wire tests.
3. Repin the flake-owned Aiken blueprint hash if required.
4. Build the strict MkDocs site.
5. Report applied checkpoint and Advance-observer sizes against 16,133 bytes.
6. Run the authorized stock-PV11 story and freeze txids/costs/rejections.
7. Run `./gate.sh` once on the exact final tree.
8. Commit one story-shaped changeset with `Closes #138`, push, and open a
   ready human-readable PR containing settled txids, sizes, costs, and docs.
9. Wait for CI green, then PARK for operator merge. Do not merge.

## Risk controls

- A size miss stops implementation; the near-limit Advance observer is not
  edited.
- The early-claim live check runs immediately after Freeze; the correct claim
  and wrong-hunter check use a node-derived post-deadline lower bound.
- Exact whole-`Value` equality prevents hidden payout assets or silent reserve
  drift.
- The immutable production blueprint is the one exercised live.
