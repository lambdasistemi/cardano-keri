# Feature Specification: convict a small identity (#151)

**Feature branch**: `story/151-convict-small`
**Created**: 2026-07-28
**Status**: Approved for implementation
**Issue**: https://github.com/lambdasistemi/cardano-keri/issues/151
**Depends on**: register-small #136, rotate-small #142, freeze-small #137,
seize-delay #138

## User scenarios

### User Story 1 — Convict from ACTIVE (P1)

A permissionless convictor presents a genuinely conflicting KERI rotation
whose controller signatures and witness receipts prove that the identity
published both branches. Convict atomically burns the checkpoint token and
pays the complete ACTIVE checkpoint value, excluding only the burned token,
to the named convictor.

**Independent proof row**: spend an ACTIVE checkpoint holding
`checkpoint_min_ada + D_reg + B`, burn exactly its quantity-one AID token, and
settle one datum-free, lovelace-only output of exactly
`checkpoint_min_ada + D_reg + B` at the named convictor key.

### User Story 2 — Convict from ARMED (P1)

An in-flight delay challenge does not erase the recorded hunter's interest.
Convict burns the checkpoint token, pays exactly
`checkpoint_min_ada + D_reg` to the named convictor, and pays exactly `B` to
the hunter stored in the ARMED datum.

**Independent proof row**: spend a well-formed ARMED checkpoint and settle two
distinct indexed outputs: the full minimum-plus-divergence reserve to the
convictor and exactly the delay bond to the recorded hunter.

### User Story 3 — Convict from FROZEN (P1)

FROZEN has already paid `B` through ClaimFreeze. Convict therefore burns the
checkpoint token and pays only `checkpoint_min_ada + D_reg` to the named
convictor. It neither invents nor pays a second delay bond.

**Independent proof row**: first settle the full freeze timeout lifecycle,
then convict the resulting FROZEN checkpoint and observe a single exact
minimum-plus-divergence payout.

### User Story 4 — Incomplete evidence cannot convict (P1)

A controller-signed private draft is not a published fork, and an event that
does not conflict with the recorded tip is not equivocation. Both candidates
fail in the applied enforcement observer before submission.

**Independent test**: remove the witness receipts from the generated
conflicting event for the unwitnessed case; use the generated recorded event
itself for the no-conflict/insufficient-evidence case.

### User Story 5 — Conviction is a burn record, not an absorbing output (P1)

The Convict transaction, redeemers, witnessed evidence, burn, and payouts are
the immutable tombstone record. It creates no TOMBSTONE UTxO. Once the token
is absent, the same AID may be registered again from genuine inception
evidence; consumers treat only the newly registered ACTIVE output as current.

## Functional requirements

- **FR-001**: `MintRedeemer` MUST add only `ConvictBurn {
  checkpoint_ref }` at constructor index 2. `Register` and `CloseBurn` MUST
  remain indices 0 and 1.
- **FR-002**: `SpendRedeemer` MUST add only `Convict {
  convictor_pkh, convictor_output_index, hunter_output_index }` at constructor
  index 4. Existing indices `Close=0`, `Advance=1`, `Freeze=2`, and
  `ClaimFreeze=3` MUST remain unchanged.
- **FR-003**: The enforcement observer MUST add only action 4 for Convict.
  Existing actions 0 through 3 and the Advance observer source MUST remain
  unchanged.
- **FR-004**: ConvictBurn MUST name the exact checkpoint input, accept only
  well-formed ACTIVE, ARMED, or FROZEN role/datum pairs, derive the AID token
  from the inner `V1` datum, burn exactly one such token under the checkpoint
  policy, and forbid that token in every output.
- **FR-005**: Convict spend MUST require the action-4 enforcement observer for
  the same checkpoint policy and named input.
- **FR-006**: The observer MUST bind the evidence to the spent checkpoint's
  AID and accept only `convict_predicate == ConvictValid`. ACTIVE and FROZEN
  carry direct `V1`; ARMED carries a well-formed `ArmedV1` wrapper whose
  checkpoint is the predicate tip.
- **FR-007**: ACTIVE Convict MUST select a datum-free, lovelace-only output at
  the named 28-byte convictor key containing exactly
  `checkpoint_min_ada + D_reg + B`.
- **FR-008**: ARMED Convict MUST select distinct convictor and hunter output
  indices. The convictor output MUST contain exactly
  `checkpoint_min_ada + D_reg`; the hunter output MUST contain exactly `B`
  and be addressed to the hunter stored in the ARMED datum.
- **FR-009**: FROZEN Convict MUST select a datum-free, lovelace-only output at
  the named convictor key containing exactly
  `checkpoint_min_ada + D_reg`. It MUST NOT require or create a hunter payout.
- **FR-010**: Every Convict source MUST require the checkpoint input assets to
  be lovelace plus exactly the quantity-one derived AID token. ACTIVE and ARMED
  MUST hold at least `checkpoint_min_ada + D_reg + B`; FROZEN MUST hold at
  least `checkpoint_min_ada + D_reg`. Convict MUST pay only the exact protected
  amounts in FR-007 through FR-009, leave any surplus lovelace as ordinary
  transaction change, and create no checkpoint-role successor or output
  containing the burned token.
- **FR-011**: The transaction/redeemer/evidence record is the terminal
  tombstone. No TOMBSTONE role output or datum is created, and no global
  once-ever registration barrier is introduced.
- **FR-012**: Unwitnessed conflict evidence and a generated event that does
  not conflict with the recorded tip MUST reject through the applied observer.
- **FR-013**: The committed keripy fixture generator and its pinned keripy
  version MUST generate the witnessed conflicting event used by the live
  proof without fixture drift.
- **FR-014**: Three stock-PV11 live rows MUST independently settle Convict
  from ACTIVE, ARMED, and FROZEN. The FROZEN row MUST first settle
  Register → Advance → Freeze → ClaimFreeze.
- **FR-015**: The live evidence MUST report every conviction txid, the exact
  source-specific payouts, token absence, the two rejected candidates, and
  the applied checkpoint/enforcement-observer sizes and costs.
- **FR-016**: The story PR MUST ship a navigable user conviction page
  explaining divergence versus delay bonds, atomic burn-record plus payouts,
  all three value rows, and re-registration after conviction.
- **FR-017**: Register, Close, Advance, Freeze, ClaimFreeze, response, and thaw
  behavior MUST remain unchanged.
- **FR-018**: The applied checkpoint and enforcement observer MUST each remain
  no larger than 16,133 bytes. The applied Advance observer MUST not grow from
  its 16,130-byte baseline.

## Key entities

- **Divergence bond (`D_reg`)**: the truth reserve forfeited only after a fully
  witnessed irreconcilable fork.
- **Delay bond (`B`)**: the smaller liveness reserve. It remains in ACTIVE and
  ARMED, belongs to the recorded hunter during ARMED conviction, and is
  already absent in FROZEN.
- **Convictor**: the permissionless submitter named by a 28-byte verification
  key hash in the Convict redeemer.
- **Conviction tombstone**: the settled transaction containing the burn,
  evidence observer redeemer, source input, and exact payouts. It is a ledger
  record, not a surviving checkpoint output.

## Success criteria

- **SC-001**: ACTIVE, ARMED, and FROZEN each have their own settled stock-PV11
  Convict txid and exact source-state value proof.
- **SC-002**: Every successful row burns the quantity-one AID token and leaves
  no checkpoint or token-bearing successor.
- **SC-003**: The generated unwitnessed and no-conflict candidates reject
  through the applied enforcement observer without submission.
- **SC-004**: Pinned keripy regeneration is drift-free.
- **SC-005**: The checkpoint and enforcement observer fit the 16,133-byte
  program budget; the Advance observer hash and 16,130-byte size are unchanged.
- **SC-006**: The conviction page builds under strict MkDocs and states the
  burn-based tombstone and all three payout rows without implying that a
  TOMBSTONE UTxO survives.
- **SC-007**: The exact reviewed tree passes `./gate.sh`, GitHub CI turns
  green, and the ready PR is parked for operator merge.

## Assumptions and boundaries

- Ratified #115 burn semantics supersede the earlier surviving-TOMBSTONE-output
  design: a UTxO must be spendable/referenced or not exist.
- `D_reg`, `B`, role tags, evidence predicates, and the stock-PV11 deployment
  parameters are frozen inputs.
- The existing keripy fixture is generated by keripy 1.3.5 through the pinned
  repository generator; no hand-authored conflicting event is admissible.
- Convict does not add a new KERI predicate. It composes the existing
  `convict_predicate` with small state, burn, and payout mechanics.
- Close, Reap, ClaimFreeze, and every other lifecycle arm remain outside this
  change.
- Machine facts are copied by reading captured command output; txids, costs,
  program sizes, and hashes are never reconstructed by hand.
