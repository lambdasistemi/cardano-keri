# Feature Specification: freeze a small identity end to end (#137)

**Feature branch**: `story/137-freeze-small`
**Created**: 2026-07-27
**Status**: Approved for implementation
**Issue**: https://github.com/lambdasistemi/cardano-keri/issues/137
**Depends on**: register-small #136, close-small #143, rotate-small #142
**Precedes**: seize-small #138

## User Scenarios & Testing

### User Story 1 — A hunter arms a lagging checkpoint (P1)

A witnessed two-key identity is registered and genuinely rotated once. The
same committed successor keys then sign two different, witness-receipted
rotations at the next sequence number. A hunter presents one contested branch
through the enforcement observer. The checkpoint moves from ACTIVE to ARMED,
records the hunter and a finite response deadline, and preserves the complete
checkpoint value.

**Why this priority**: a public checkpoint must fail closed when the published
KERI history proves that its ACTIVE state is behind a contested next event.
The transition must be permissionless without making lag immediately
profitable.

**Independent test**: settle Register and the first Advance, submit one genuine
keripy-produced branch of the next witnessed double-sign, and observe a
quantity-one checkpoint token at the ARMED role with the exact inner datum,
hunter, deadline, and unchanged value.

**Acceptance scenarios**:

1. **Given** an ACTIVE checkpoint at the first witnessed rotation, **when** a
   hunter submits a second witnessed rotation revealing keys committed by the
   checkpoint, **then** Freeze settles.
2. **Given** two sibling second rotations signed by the same revealed keys and
   receipted by the incoming witness quorum, **then** the committed fixture
   proves that the submitted evidence is genuine contested-rotation material,
   not synthetic bytes.
3. **Given** a settled Freeze, **then** consumers see the token at the ARMED
   `0x02` role, the hunter is recorded exactly, and the entire input value
   including `D_reg+B` remains in checkpoint custody.

### User Story 2 — The honest controller answers before the deadline (P1)

The controller responds to an ARMED challenge with the other genuine sibling
rotation. The ordinary Advance path validates the rotation against the inner
checkpoint datum, returns the token to ACTIVE, and keeps the complete bond.

**Independent test**: consume the ARMED output with the recorded sibling
rotation under a finite validity upper bound strictly before the stored
deadline, then observe the exact ACTIVE successor and unchanged value.

**Acceptance scenarios**:

1. The Advance observer unwraps the ARMED datum only to obtain the prior
   checkpoint state; the heavy rotation predicate remains unchanged.
2. A response with a finite upper endpoint before the deadline settles and
   returns exactly one ACTIVE successor.
3. The successor carries the exact rotation-derived datum and the complete
   ARMED value, so the hunter receives no bond when the owner responds.
4. A response at or after the deadline rejects.

### User Story 3 — Invalid Freeze evidence cannot arm (P1)

The checkpoint rejects evidence that is for another AID, is not ahead, does
not reveal keys committed by the checkpoint, is below the prior controller
threshold, or lacks the required witness receipts.

**Independent test**: execute the existing generated enforcement negatives
through the coupled applied checkpoint and enforcement-observer boundary and
observe rejection before any state transition.

## Edge Cases

- Missing, non-zero, wrong-action, wrong-policy, or wrong-outref enforcement
  withdrawals reject.
- A malformed hunter key hash, missing finite validity upper endpoint, wrong
  deadline, wrong role, duplicate ARMED successor, changed value, missing
  token, or own-policy mint/burn rejects.
- Freeze from ARMED, FROZEN, or any malformed role/datum combination rejects.
- An ARMED response with an unbounded upper endpoint or an endpoint at the
  deadline rejects.
- ClaimFreeze remains unavailable and fail-closed until #138.
- Register, Close, and ordinary ACTIVE Advance behavior remain unchanged.

## Functional Requirements

- **FR-001**: The checkpoint Freeze arm MUST be thin: it checks state, role,
  value, token, hunter, deadline, and the exact zero-lovelace
  `observer_enforcement` claim, but MUST NOT import or execute the heavy
  enforcement predicate.
- **FR-002**: `observer_enforcement` MUST resolve the named checkpoint input,
  bind the unchanged `EnforcementEvidence`, and run the unchanged
  `freeze_predicate`.
- **FR-003**: The stable observer action tag for Freeze MUST be `2`; Register
  remains `0`, ACTIVE Advance remains `1`, and ARMED response Advance uses
  `3` so the heavy observer selects the correct datum wire without duplicating
  state-role derivation owned by the thin checkpoint arm.
- **FR-004**: Freeze MUST consume one ACTIVE/V1 checkpoint and create exactly
  one ARMED/ArmedV1 successor containing the unchanged inner checkpoint,
  exact 28-byte hunter hash, and `deadline = finite_upper + W_freeze`.
- **FR-005**: Freeze MUST preserve the complete input Value, retain the
  quantity-one AID token and the `checkpoint_min_ada + D_reg+B` reserve, and
  mint or burn nothing under the checkpoint policy.
- **FR-006**: Freeze evidence MUST be a rotation strictly ahead of the tip,
  reveal keys committed by `next_keys`, satisfy `next_threshold`, and carry
  at least the recorded witness `toad` over the exact event bytes.
- **FR-007**: Ordinary Advance MUST accept an ARMED input only when its finite
  validity upper endpoint is strictly before the stored deadline; it MUST
  validate the rotation against the inner checkpoint and create one ACTIVE
  successor with the complete input Value.
- **FR-008**: ClaimFreeze MUST remain fail-closed. No payout, seizure,
  enforcement-conviction, Frozen transition, bond release, or hunter bounty
  mechanism may be added.
- **FR-009**: The live story MUST use keripy-produced sibling rotations signed
  by the same committed controller keys and witness-receipted at the required
  threshold; one branch Arms and the other is the response Advance.
- **FR-010**: Applied-boundary tests MUST reject at least the wrong-AID or
  uncommitted-reveal family, the prior-controller-threshold family, and the
  insufficient-witness family.
- **FR-011**: The applied checkpoint and applied
  `observer_enforcement` programs MUST each be no larger than 16,133 bytes.
- **FR-012**: Existing Register, Close, and ACTIVE Advance suites MUST remain
  green.

## Key Entities

- **Contested rotation pair**: two different keripy rotations at the same next
  sequence number, signed by the same revealed controller keys and receipted
  by the same incoming witness quorum.
- **Freeze evidence**: the submitted contested branch, encoded as the existing
  `EnforcementEvidence` and checked by the enforcement observer.
- **ARMED checkpoint**: role `0x02`, complete checkpoint value, and
  `ArmedV1 { checkpoint, hunter_pkh, deadline }`.
- **Response Advance**: the other sibling rotation, admitted by the unchanged
  Advance predicate before the stored deadline.

## Ratified Evidence

The story reuses the #106 enforcement binding and Freeze predicate, the #116
bond/deadline/role model, and the #142 Advance observer. The new fixture is
generated by the existing pinned keripy 1.3.5 harness and self-verifies every
controller signature and witness receipt over the exact event bytes.

The abstract lifecycle proofs and executable traceability already cover
ACTIVE-to-ARMED exclusivity, the bounded response window, and
advance-totality. This story wires those ratified rules into the small applied
scripts; it does not change the pure lifecycle model.

## Success Criteria

- **SC-001**: Register, first Advance, Freeze, and response Advance all settle
  on a stock PV11 devnet, with txids captured.
- **SC-002**: The ARMED output records the hunter and exact deadline while
  preserving 100% of the checkpoint input value.
- **SC-003**: The response returns to ACTIVE before the deadline with 100% of
  the value, including the bond, preserved.
- **SC-004**: The named invalid/insufficient evidence families reject through
  the coupled applied-validator boundary.
- **SC-005**: Both applied scripts fit the 16,133-byte program budget and the
  full repository gate passes.

## Assumptions and Boundaries

- The #106 evidence format and predicate are frozen inputs. A contested branch
  is sufficient to Arm because Freeze protects a lagging/ambiguous projection;
  terminal fork conviction is a different action and is not opened here.
- The #116 `B`, `W_freeze`, ARMED role, raw endpoint semantics, and complete
  Value preservation are frozen inputs.
- This story opens only Freeze and the already-ratified ARMED response through
  Advance. ClaimFreeze remains closed for #138.
- No Frozen/Tombstone output, seizure, enforcement conviction, bond payout,
  Arm/Claim legacy path, or unrelated observer family is in scope.
