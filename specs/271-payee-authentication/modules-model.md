# Modules model — #271 enforcement bounty entitlement

Artifact ceiling: 8,000 bytes and 160 lines.

This model owns changed responsibilities and dependency direction. Data is in
`data-model.md`; changed signatures are in `functions-model.md`.

## Components and modules

### `MOD-271-PROTOCOL` — shared entitlement protocol

- Owns versioned commitment action, scope, opaque preimage, evidence digest,
  marker identity, reveal, timing, and structured verdict data.
- Owns no checkpoint state transition, KERI predicate, transaction builder,
  provider, wallet, or deployment selection.
- Is the nearest stable upstream owner shared by commitment validation,
  enforcement observation, offchain encoding, and generated parity vectors.

### `MOD-271-COMMITMENT` — bounty commitment validator/policy

- Owns authentic unique-marker opening, applied age/lifetime/deposit parameters,
  reveal consumption/refund, marker burn, and expired sweep.
- Proves creation came through policy checks; an arbitrary script-address UTxO
  confers no entitlement.
- Depends on **MOD-271-PROTOCOL** and ledger primitives, never on KERI evidence
  semantics or checkpoint datum internals.

### `MOD-271-CHECKPOINT` — deployed split checkpoint family

- `onchain/validators/checkpoint_register.ak` continues to own thin role,
  datum, token, reserve, payout-index, and observer-coupling checks.
- Requires the commitment policy and exact commitment reference for Freeze and
  Convict. It records the proven hunter commitment identity in `ArmedV2`.
- Claim and ARMED hunter payout consume only stored entitlement; no fresh
  caller may select that beneficiary and no fresh signature may veto progress.

### `MOD-271-OBSERVER` — enforcement observer

- `checkpoint_observer` / `checkpoint/enforcement_observer` continue to own
  binding and evaluation of the actual Freeze/Convict evidence.
- Additionally derive its canonical digest and reconcile it with the mature,
  unexpired commitment named by the checkpoint action.
- Return no generic “signer present” verdict; entitlement scope and evidence
  matching are inseparable at this boundary.

### `MOD-271-MIRROR` — combined checkpoint and compiled proof target

- `onchain/validators/checkpoint.ak`, its tests, measurements, and M8 selection
  mirror the split family semantics.
- May share **MOD-271-PROTOCOL** but must not become an alternate wire protocol
  or retain the signer-only defect.

### `MOD-271-OFFCHAIN` — wire, builders, and parity

- The stable offchain checkpoint library owns versioned Haskell mirrors,
  canonical encoding, marker/preimage derivation, and generated Aiken vectors.
- Deployment transaction construction owns commit, reveal, refund, sweep,
  required-signer, reference, and exact-output assembly.
- Evidence acquisition remains separate; builders receive resolved evidence and
  commitment state rather than inventing entitlement during final assembly.

### `MOD-271-RELEASE` — #254 registry and migration integration

- #254's successor family owns the new checkpoint/ARMED version, applied
  commitment policy/parameters, reference script, release registry entry, and
  migration/cutover boundary.
- Historical v0 entries remain immutable and explicitly unprotected.
- #253 board code has no dependency on entitlement protocol; both meet only in
  the release registry and coordinated cutover.

## Dependency edges

- **EDGE-271-01:** commitment validator → shared entitlement protocol.
- **EDGE-271-02:** enforcement observer → shared entitlement protocol.
- **EDGE-271-03:** split checkpoint → entitlement types/identity and observer
  verdict, never to offchain construction.
- **EDGE-271-04:** combined mirror → the same shared protocol rows.
- **EDGE-271-05:** offchain parity/builders → shared protocol mirror; no reverse
  edge from onchain code.
- **EDGE-271-06:** #254 release integration → checkpoint, commitment, offchain
  artifacts; #271 does not depend on #253 board implementation.

## Promotion and boundary decisions

- **PROMOTE-271-01:** Commitment scope/preimage/verdict data belong in the
  shared checkpoint protocol, not duplicated in validator files.
- **PROMOTE-271-02:** KERI `EnforcementEvidence` remains in enforcement; only its
  canonical digest crosses into entitlement.
- **PROMOTE-271-03:** `ArmedV2` belongs to the #254 versioned checkpoint state,
  because changing frozen `ArmedV1` in place is forbidden.
- **PROMOTE-271-04:** Registry and deployed magnitudes belong to #254 release
  data; pure entitlement types contain no ambient manifest or network lookup.

## Mechanical boundaries

- Split and combined programs consume the same generated commitment vectors and
  invariant cases.
- No Freeze/Convict transaction builder omits the commitment reference, marker
  burn, exact refund, or required selection-time signer.
- No old manifest entry is overwritten and no v0 script is labeled protected.
- Commitment code cannot authorize a KERI event; enforcement code cannot mint
  an entitlement without the commitment policy.
