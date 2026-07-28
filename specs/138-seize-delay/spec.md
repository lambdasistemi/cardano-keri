# Feature Specification: claim an unanswered freeze bond and thaw (#138)

**Feature branch**: `story/138-seize-delay`
**Created**: 2026-07-28
**Status**: Approved for implementation
**Issue**: https://github.com/lambdasistemi/cardano-keri/issues/138
**Depends on**: register-small #136, rotate-small #142, freeze-small #137

## User scenarios

### User Story 1 — An unanswered challenge pays the recorded hunter (P1)

A witnessed identity has advanced once and is then challenged with a genuine
later KERI event. The checkpoint is ARMED with a recorded hunter and a hard
deadline. If no response Advance settles before that deadline, anyone may
submit `ClaimFreeze`; the transaction pays exactly the delay bond `B` to the
recorded hunter and leaves the checkpoint FROZEN with the quantity-one AID
token, unchanged `V1` datum, and `checkpoint_min_ada + D_reg`.

**Independent test**: consume an ARMED checkpoint under a finite validity
lower bound at or after its stored deadline. Observe one lovelace-only,
datum-free output of exactly `B` at the recorded hunter key and one FROZEN
successor whose complete value is the input value minus exactly `B`.

### User Story 2 — A frozen checkpoint can catch up by re-posting B (P1)

FROZEN is not terminal. A permissionless submitter presents the real next KERI
rotation through the existing Advance observer and contributes a fresh `B`.
The checkpoint returns to ACTIVE at the next sequence with the exact successor
datum and complete value equal to the FROZEN input plus `B`.

**Independent test**: after a settled Claim, submit the genuine sibling
rotation from the #137 fixture through ordinary `Advance`. Observe an ACTIVE
successor with the quantity-one AID token, the rotation-derived `V1` datum,
and `checkpoint_min_ada + D_reg + B`.

### User Story 3 — Claim cannot be raced or redirected (P1)

The ARMED datum, not the submitter, determines the beneficiary and timing.
A claim whose finite lower endpoint is before the deadline rejects. A claim
whose named payout output is addressed to any key other than the recorded
hunter rejects, even after the deadline.

**Independent test**: evaluate both candidates through the applied checkpoint
program and observe phase-2 rejection without submission.

### User Story 4 — The complete freeze lifecycle is user-facing (P1)

The story ships a user page explaining the whole domain in one place:
challenge, response, timeout claim, and thaw. It distinguishes the delay bond
`B` from `D_reg`, explains who may submit each transition, and states exactly
when value moves.

## Functional requirements

- **FR-001**: `SpendRedeemer` MUST add only `ClaimFreeze {
  hunter_output_index }` at constructor index 3. Existing `Close`, `Advance`,
  and `Freeze` constructor indices MUST remain 0, 1, and 2.
- **FR-002**: ClaimFreeze MUST accept only an ARMED role input with a
  well-formed `ArmedV1` datum and the quantity-one AID token.
- **FR-003**: ClaimFreeze MUST require a non-empty validity interval with a
  finite raw lower endpoint `lower >= deadline`.
- **FR-004**: The output selected by `hunter_output_index` MUST be at the
  recorded 28-byte verification-key hash, carry exactly `B` lovelace, carry no
  other assets, and have no datum.
- **FR-005**: ClaimFreeze MUST create exactly one FROZEN role output carrying
  the unchanged inner `V1` datum, the AID token, and a complete value equal to
  the ARMED input value minus exactly `B`.
- **FR-006**: The FROZEN output MUST retain at least
  `checkpoint_min_ada + D_reg`; no own-policy mint or burn is permitted.
- **FR-007**: Ordinary `Advance` MUST admit a FROZEN `V1` input through the
  existing Advance observer action 1 and unchanged heavy rotation predicate.
- **FR-008**: A thaw successor MUST be ACTIVE, carry the exact
  rotation-derived `V1` datum and AID token, and have complete value equal to
  the FROZEN input value plus exactly `B`.
- **FR-009**: ARMED response Advance MUST retain its existing action 3,
  before-deadline rule, and complete-value preservation.
- **FR-010**: Register, Close, ACTIVE Advance, Freeze, and response Advance
  behavior MUST remain unchanged. No Convict, Reap, CloseIntent, or other
  lifecycle arm is opened.
- **FR-011**: The applied checkpoint program and unchanged applied Advance
  observer MUST each remain no larger than 16,133 bytes.
- **FR-012**: The live stock-PV11 story MUST settle:
  Register → first Advance → Freeze → ClaimFreeze → thaw-Advance.
- **FR-013**: The live proof MUST independently reject an early claim before
  the deadline and a wrong-hunter claim at or after the deadline.
- **FR-014**: The story PR MUST add a navigable user-facing freeze lifecycle
  page covering challenge, response, timeout claim, and thaw.

## Key entities

- **Delay bond (`B`)**: the 5 ADA deployment parameter held in ACTIVE and
  ARMED, paid only after a complete unanswered freeze window, and re-posted on
  thaw.
- **Registration deposit (`D_reg`)**: the distinct protected deposit retained
  by FROZEN. ClaimFreeze never pays it.
- **ARMED checkpoint**: role `0x02`, `ArmedV1 { checkpoint, hunter_pkh,
  deadline }`, and complete `min + D_reg + B` reserve.
- **FROZEN checkpoint**: role `0x00`, plain `V1` datum, quantity-one AID token,
  and `min + D_reg`.
- **Thaw**: ordinary permissionless Advance from FROZEN to ACTIVE, applying
  the real next KERI event and adding a fresh `B`.

## Success criteria

- **SC-001**: A settled ClaimFreeze txid pays the recorded hunter exactly `B`
  and leaves the FROZEN checkpoint with `min + D_reg`.
- **SC-002**: A settled thaw-Advance txid returns the checkpoint to ACTIVE
  with the real successor datum and a re-posted `B`.
- **SC-003**: Wrong-hunter and early-claim candidates reject through the
  applied program without submission.
- **SC-004**: The checkpoint and Advance observer fit the 16,133-byte program
  budget, and the full repository gate passes.
- **SC-005**: The freeze lifecycle user page builds under strict MkDocs and
  accurately describes challenge, response, timeout claim, and thaw.

## Assumptions and boundaries

- The #116 bond amount, deadline arithmetic, role tags, and value-conservation
  model are frozen inputs.
- The #137 `Freeze` arm, ARMED wrapper, fixture, and response behavior are
  frozen inputs.
- The #142 heavy Advance predicate and observer action 1 are reused unchanged.
- `ClaimFreeze` is a state/value/timing arm; it needs no evidence observer.
- Devnet machine facts, txids, program sizes, and observed costs are captured
  directly from logs and are not manually reconstructed.
