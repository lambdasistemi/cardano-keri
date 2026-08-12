# Tasks — #271 enforcement bounty entitlement

Artifact ceiling: 8,000 bytes and 180 lines.

All tasks are unchecked. Implementation is carried as a distinct slice in
#254's entitlement-aware checkpoint family; #163/#164 remain blocked through
the family cutover.

## Contract adoption

- [ ] **T271-001** Obtain the #254 batching ruling and incorporate S271-1
  through S271-3 plus every `INV-271-*` row without reducing them to signer
  membership.
- [ ] **T271-002** Version the #254 checkpoint/ARMED schema and registry for the
  commitment policy, reference, one-slot age, 10,000-slot lifetime, deposit,
  and historical v0 exposure boundary.
- [ ] **T271-003** Initialize the campaign ledger with all eight BLOCKING rows
  OPEN, `builds_spent=0`, `builds_budget=3`, and the set-point/tail/overrun rule.

## S271-1 — commitment protocol

- [ ] **T271-101** Add **DAT-271-SCOPE**, **DAT-271-PREIMAGE**,
  **DAT-271-COMMITMENT**, reveal/sweep data, and generated Haskell/Aiken
  canonical vectors with versioned wire identifiers.
- [ ] **T271-102** Implement authentic seed-derived marker opening with exact
  confinement/value/timing and creation-time payee signer.
- [ ] **T271-103** Implement mature reveal/refund and expired sweep with exact
  marker burn, deposit routing, signer, and validity boundaries.
- [ ] **T271-104** Demonstrate counterfeit-output, copied-hash, duplicate marker,
  missing signer, wrong deposit/refund, same-slot reveal, post-expiry reveal,
  and premature-sweep RED before GREEN.
- [ ] **T271-105** Demonstrate every scope/preimage mutation in
  `INV-271-SCOPE` rejects and remains covered by a permanent property.

## S271-2 — enforcement integration

- [ ] **T271-201** Require the actual observer evidence digest and a matching
  mature Freeze commitment for ACTIVE to `ArmedV2`; record hunter plus marker
  identity and refund the commitment deposit exactly.
- [ ] **T271-202** Preserve ClaimFreeze's exact recorded-hunter bond payout and
  prove a caller cannot substitute the beneficiary or impose a fresh hunter
  witness requirement.
- [ ] **T271-203** Require a matching Convict commitment for ACTIVE, ARMED, and
  FROZEN; prove each exact convictor reserve and commitment refund.
- [ ] **T271-204** Preserve ARMED's distinct recorded-hunter payout and prove
  neither redirection nor fresh-signature veto is possible.
- [ ] **T271-205** Apply the same rules to the deployed split validator,
  enforcement observer, combined mirror, offchain builders, measurements, and
  M8 compiled selection.
- [ ] **T271-206** Demonstrate the original substituted-payee transaction: it
  passes the pre-fix/signer-only mutant and fails the entitlement-aware family
  for the intended reason on every unbound inventory row.

## S271-3 — release and migration integration

- [ ] **T271-301** Publish commitment/checkpoint program identities, references,
  parameters, predecessor edge, and earliest scan point in #254's append-only
  registry without replacing v0 history.
- [ ] **T271-302** Extend no-secret deployment packages for commit, reveal,
  sweep, required signers, exact values, references, and settlement identities.
- [ ] **T271-303** Prove migration creates the entitlement-aware versioned
  checkpoint/ARMED family and never describes old v0 outputs as repaired.
- [ ] **T271-304** Add the #163/#164 readiness condition: no hunter journey or
  incentive claim opens before the protected family is deployed.

## Verification and acceptance

- [ ] **T271-401** Settle every declared invariant as KILLED or BLOCKED with a
  named failing mutant and permanent property; no BLOCKING residual is accepted.
- [ ] **T271-402** Run focused commitment/enforcement parity, boundary, race,
  value, builder, split/mirror, and M8 compiled checks plus full repository CI
  within the build budget.
- [ ] **T271-403** Verify applied program sizes without weakening entitlement;
  if the checkpoint crosses its limit, move heavy matching across the existing
  observer boundary and rerun the complete proof.
- [ ] **T271-404** Verify exact audited tree, task stamps, campaign state,
  #254 registry identities, PR history, and issue linkage before publication.
- [ ] **T271-405** At #254 acceptance and again at cutover, announce the new M8
  targets and the exact point after which enforcement bounty theft is closed.

## Ordering

`T271-001..003 -> S271-1 -> S271-2 -> S271-3 -> T271-401..405`.

S271-1 and S271-2 are serial because an enforcement branch cannot claim
entitlement before marker lifecycle/parity is complete. S271-3 composes with
#254's registry and cutover work. #253 can proceed on its board slice, but the
shared release is not ready until both families and their proofs are accepted.
