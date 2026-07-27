# Feature Specification: rotate a small identity end to end (#142)

**Feature branch**: `story/142-rotate-small`
**Created**: 2026-07-27
**Status**: Draft
**Issue**: https://github.com/lambdasistemi/cardano-keri/issues/142
**Depends on**: register-small #136 and close-small #143

## User Scenarios & Testing

### User Story 1 — Advance a witnessed two-key identity (P1)

After a small registered identity publishes a genuine KERI rotation, any
submitter can move its checkpoint from the registered state to the exact
rotated state. The identity's escrow and checkpoint token remain in the
ACTIVE state output.

**Why this priority**: rotation is the first useful state transition after
registration. Freeze and recovery cannot be meaningful until the checkpoint
can follow an honest rotation.

**Independent test**: register the two-key fixture, submit its real keripy
witnessed rotation, and observe the Advance transaction settle with exactly one
ACTIVE successor.

**Acceptance scenarios**:

1. **Given** the registered state matching the witnessed two-key fixture,
   **when** anyone submits the fixture's rotation-key controller signatures and
   incoming-set witness receipts, **then** Advance settles.
2. **Given** that Advance settles, **then** the successor carries the same
   checkpoint token and complete value, and its datum is exactly the state
   derived from the rotation.
3. **Given** the same rotation package, **when** a different submitter relays
   it, **then** the result is identical; no submitter signature grants KERI
   authority.

### User Story 2 — Reject unauthorized rotation (P1)

An attacker cannot rotate the checkpoint with stolen current keys, too few
new-controller signatures, or too few incoming-set witness receipts.

**Independent test**: replay the ratified #115 rejection vectors through the
same transaction-level Advance path and observe all three reject.

**Acceptance scenarios**:

1. The spent current keys alone cannot authorize the successor.
2. A controller package below the successor threshold rejects.
3. A witnessed identity with receipts below the incoming `toad` rejects.

## Edge Cases

- A valid event with a different spent output reference rejects.
- A second ACTIVE successor, missing token, extra own-policy mint, or changed
  escrow rejects.
- A successor that changes any datum field not determined by the rotation
  rejects.
- Cut witnesses do not count toward the incoming receipt quorum.
- Register and Close behavior remain unchanged.

## Functional Requirements

- **FR-001**: The thin checkpoint Advance arm MUST consume the named ACTIVE
  checkpoint input, require the zero-lovelace `observer_advance` withdrawal
  with its exact claim, and create exactly one ACTIVE successor.
- **FR-002**: The successor MUST preserve the complete input value byte-for-byte
  at the ledger-value level; the checkpoint token moves and is neither minted
  nor burned.
- **FR-003**: The `observer_advance` reference script MUST run the ratified
  #115 `advance_predicate` over the named spent datum, unique successor, and
  forwarded evidence: spent outref, policy, AID, `seq + 1`, increasing native
  sequence, key pre-rotation, witness delta, and `toad` all bind.
- **FR-004**: Controller signatures MUST cover the reconstructed Advance
  message with the event's own new keys; signatures from the spent current keys
  MUST NOT substitute for the committed next-key proof.
- **FR-005**: Witness receipts MUST cover the exact keripy event bytes and meet
  the incoming-set threshold after cuts and additions.
- **FR-006**: Advance MUST be permissionless to relay and introduce zero
  submitter-selected state degrees of freedom.
- **FR-007**: The positive path and the stolen-current, under-signed, and
  under-witnessed families MUST execute at the applied validator boundary.
- **FR-008**: Register and Close MUST remain behaviorally unchanged.
- **FR-009**: Both the applied checkpoint and applied `observer_advance`
  programs MUST be no larger than 16,133 bytes.

## Key Entities

- **Spent checkpoint**: the ACTIVE token, full escrow value, inline V1 datum,
  and exact output reference being advanced.
- **Advance evidence**: genuine keripy rotation bytes, locating offsets,
  witness cut/add delta, event-own controller signatures, and incoming-set
  witness receipts.
- **Successor checkpoint**: the single ACTIVE output whose value is preserved
  and whose V1 datum is completely determined by the evidence and spent state.

## Ratified Evidence

This story reuses the generated Aiken vectors in
`onchain/lib/cardano_keri/checkpoint/advance_vectors.ak`; it does not invent a
new rotation fixture or wire format. The #115 applied-validator measurements
record the witnessed two-key path at 4,226,861 of 14,000,000 memory and
2,046,910,284 of 10,000,000,000 CPU. The larger seven-key row is the existing
suite maximum at 7,612,741 of 14,000,000 memory, demonstrating that the
ratified predicate already fits stock limits with headroom.

## Success Criteria

- **SC-001**: One genuine witnessed two-key Advance transaction settles on a
  stock PV11 devnet after a Register settlement.
- **SC-002**: All three authority rejection families fail at the same applied
  validator boundary.
- **SC-003**: The successor preserves 100% of the checkpoint input value and
  has exactly the datum dictated by the rotation.
- **SC-004**: The full gate passes without weakening the existing #115
  predicate, vectors, Register tests, or Close tests.

## Assumptions and Boundaries

- The #115 message layout, vector generator, predicates, and receipt rule are
  frozen inputs and are not redesigned here.
- Only the small witnessed two-key vertical is delivered live in this story;
  seven-key and other #115 families remain regression/measurement evidence.
- Freeze, seize, Arm, Claim, enforcement-observer work, and bond/hunter logic
  are out of scope. This story opens only the Advance observer family.
