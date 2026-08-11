# Tasks — #254 validator-version migration

Artifact ceiling: 7,000 bytes and 160 lines.

All tasks are unchecked. The machine build gate is a hard prerequisite for any
implementation, proof execution, child seating, or audit.

## Phase 1 — dependency and contract freeze

- [ ] T254-001 Rebase `feat/254-validator-migration` onto current
  `origin/main`, retaining the six mandate files and incorporating constitution
  `a716f4b` plus the current PR template before any behavior work.
- [ ] T254-002 Obtain the epic ruling on batching #271 into S254-1; freeze
  the exact owned paths only after that answer.
- [ ] T254-003 Negotiate the version-registry and resolved-result contract
  with #171 through the milestone desk; version this mandate if the agreed seam
  changes any producer field or invariant.
- [ ] T254-004 Freeze the preproduction v0 checkpoint/board policies,
  references, network parameters, earliest scan point, and three expected board
  witness identities as legacy bridge inputs.
- [ ] T254-005 Initialize the runtime campaign ledger with all eight
  BLOCKING rows OPEN, `builds_spent=0`, `builds_budget=3`, and the tail/overrun
  rule from `plan.md`.

## Phase 2 — S254-1 checkpoint family

- [ ] T254-101 [US1] Add the shared version, predecessor-origin, target,
  and canonical migration-authorization models in onchain/offchain parity.
- [ ] T254-102 [US1] Demonstrate RED for missing/foreign/below-threshold
  current-controller authorization and GREEN for permissionless relay of the
  same controller-signed package.
- [ ] T254-103 [US1] Demonstrate RED for redirect/replay mutants changing
  source outref, policy/version, target, role/state, or legacy refund.
- [ ] T254-104 [US1] Implement and prove permanent N migrate-out plus pinned
  N+1 migrate-in with exact role, datum, token, and value continuity.
- [ ] T254-105 [US1] Implement and prove the exact preproduction v0 ACTIVE
  `Close`/`CloseBurn` bridge, including refund plus equal successor
  capitalization and rejection of v0 ARMED/FROZEN rows.
- [ ] T254-106 [US1] Generate cross-layer vectors and prove byte/verdict
  parity; no generated Aiken vector is hand edited.
- [ ] T254-107 [US1] If #271 batching is accepted, require authenticated
  hunter/convictor payees throughout the touched checkpoint branches and
  demonstrate substituted-payee RED before #163/#164.
- [ ] T254-108 [US1] Register the exact changed compiled checkpoint family
  with M8 and kill named authority and replay mutants against that target.

## Phase 3 — S254-2 board family

- [ ] T254-201 [US2] Add version/origin board envelopes without interpreting
  or weakening the target endpoint-authentication schema.
- [ ] T254-202 [US2] Implement and prove permanent board N migrate-out and
  pinned N+1 migrate-in with owner, witness marker, content, deposit, and target
  authentication continuity.
- [ ] T254-203 [US2] Implement and prove the frozen v0 `Retire`/`Burn`
  bridge, same-name successor confinement, target authentication, and exact
  predecessor origin.
- [ ] T254-204 [US2] Provide #253's target-schema handoff and require the
  first deployed successor to contain owner+sequence binding; do not deploy an
  intermediate unhardened version.
- [ ] T254-205 [US2] Demonstrate missing/duplicate/changed-row and partial
  three-record inventory RED, then reconcile all three expected witnesses.
- [ ] T254-206 [US2] Generate board parity vectors and register the exact
  compiled board target with M8 authority/replay checks.

## Phase 4 — S254-3 registry and consumer-ready cutover surface

- [ ] T254-301 [US3] Add and validate the append-only multi-version release
  registry with checkpoint role addresses, board addresses, predecessor edges,
  references, source identities, and earliest scan point.
- [ ] T254-302 [US3] Preserve the committed v0 manifests as immutable
  history and publish the target as a new registry entry, never a replacement.
- [ ] T254-303 [US3] Add no-secret checkpoint/board migration package
  preparation and one-for-one dry-run inventory reconciliation without live
  submission.
- [ ] T254-304 [US3] Prove the consumer example can obtain version, policy,
  outref, and current KEL authority from the family-neutral producer result
  without a single-address assumption.
- [ ] T254-305 [US3] Hand the exact registry schema, origin semantics, and
  simulated old/new stream to #171 through the desk for its follower/query/
  relayer blindness proof.
- [ ] T254-306 [US3] Document the cutover preflight, temporary v0 liquidity,
  controller/witness package flow, reconciliation format, rollback boundary,
  and explicit no-live-submit limit.

## Verification and acceptance

- [ ] T254-401 Prove every declared invariant with at least one named mutant
  shown RED and its permanent property GREEN; update the campaign ledger row by
  row without closing any BLOCKING row as residual.
- [ ] T254-402 Complete focused onchain/offchain parity, package, registry,
  inventory, and consumer-contract checks plus full repository CI under the
  machine gate and build budget.
- [ ] T254-403 Reconcile the final compiled checkpoint/board identities with
  the M8 registered targets and record both acceptance-time announcements.
- [ ] T254-404 Produce a reproducible no-submit preproduction dry-run from
  the committed v0 inventories to the target family, showing every checkpoint
  and all three board rows pairable with no orphan.
- [ ] T254-405 Obtain the #171 seam acceptance and cutover-readiness proof;
  #254 cannot declare the preproduction event unblocked from producer evidence
  alone.
- [ ] T254-406 Verify all task stamps, exact audited tree, campaign terminal
  state, history, draft PR description, and final commit before push/review.
- [ ] T254-407 After #253, #171, M8, and the desk cutover gate are satisfied,
  execute the first real preproduction migration: carry every inventoried
  checkpoint plus all three live board records, retain the raw reproducible
  transcript, and prove identity/value/lineage continuity with unauthorized
  and replay rejection. No rehearsal migration precedes it.

## Ordering

`T254-001..005 -> S254-1 -> S254-2 -> S254-3 -> T254-401..406 -> T254-407`.

S254-1 and S254-2 share protocol types and therefore are not independent.
#253 finalizes the target board schema after the S254-2 contract exists and
before any successor deployment. #171 consumer implementation may proceed
after T254-003/T254-305 but cutover readiness waits for both sides.
