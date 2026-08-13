# Tasks — #254 migration

Artifact ceiling: 7,000 bytes and 160 lines.

The machine build gate precedes implementation and audit.

## Phase 1 — dependency and contract freeze

- [x] T254-001 Rebase `feat/254-validator-migration` onto current
  `origin/main`, retaining the six mandate files and incorporating constitution
  `a716f4b` plus the current PR template before any behavior work.
- [x] T254-002 Obtain the epic ruling on batching #271 into S254-1; freeze
  the exact owned paths only after that answer.
- [ ] T254-003 Negotiate the release-hash registry/resolved-result contract
  with #171 through the desk; amend producer fields/invariants if needed.
- [ ] T254-004 Freeze v0 checkpoint/board policies, references, network, scan
  point, and three board witnesses as legacy inputs.
- [x] T254-005 Initialize the runtime campaign ledger and carry its charged
  extensions through A-007: all BLOCKING rows retain evidence,
  `builds_spent=8`, `builds_budget=10`, allocated by `plan.md`.

## Phase 2 — S254-1 checkpoint family

- [x] T254-101 [US1] Remove the superseded version/origin datum models; retain
  only demonstrated target and canonical migration-authorization fields in
  onchain/offchain parity, with release identity supplied by applied hash.
- [x] T254-102 [US1] Demonstrate RED for missing/foreign/below-threshold
  current-controller authorization and GREEN for permissionless relay of the
  same controller-signed package.
- [x] T254-103 [US1] Demonstrate RED for redirect/replay mutants changing
  source outref/policy, target, role/state, or legacy refund, including stale
  signed state against the actually consumed input.
- [x] T254-104 [US1] Implement and prove permanent migrate-out plus a successor
  applied with one predecessor policy, with exact role, datum, token, atomic
  predecessor spend, and value continuity.
- [x] T254-105 [US1] Implement and prove the exact preproduction v0 ACTIVE
  `Close`/`CloseBurn` bridge, including refund plus equal successor
  capitalization and rejection of v0 ARMED/FROZEN rows.
- [x] T254-106 [US1] Generate cross-layer vectors and prove byte/verdict
  parity; no generated Aiken vector is hand edited.
- [x] T254-108 [US1] Register the exact changed compiled checkpoint family
  with M8 and kill named authority and replay mutants against that target.

## Phase 3 — S254-R register derivation repair

- [x] T254-109 [US1] Drop the cut-version remnant from register deployment;
  prove every live-blueprint validator's declared/applied arity agrees, sweep
  deployment/serialization/manifests for other version remnants, register M8
  against the corrected identity, and pass fresh audit build 8/10 before push.

## Phase 4 — S254-E enforcement entitlement integration

- [x] T254-107 [US1] Adopt the revised #271 standalone commitment component at
  `03da8a72e3a58d63ca4268bdfd6157e41a7ebf33` byte-identically under manifest
  `03ad05e8a32c97b9ee456beb698a4e93b9974d1ba2b0607bc83cada054586895` and
  integrate it without restating internal fields; demonstrate substituted-
  entitlement RED. Charge build 3/3 to #271's ledger for one combined audit
  and obtain its owner review through the epic owner.

## Phase 5 — S254-2 board family

- [ ] T254-201 [US2] Use the target board schema directly, with no generic
  version/origin envelope and without weakening endpoint authentication.
- [ ] T254-202 [US2] Implement and prove permanent board migrate-out and
  applied-predecessor migrate-in with owner, witness marker, content, deposit,
  and target authentication continuity.
- [ ] T254-203 [US2] Implement and prove the frozen v0 `Retire`/`Burn`
  bridge, same-name successor confinement, target authentication, and exact
  predecessor input spend in the same transaction.
- [ ] T254-204 [US2] Provide #253's target-schema handoff and require its
  accepted authentication unchanged in the first deployed successor; deploy
  no intermediate unhardened version and restate no internal fields.
- [ ] T254-205 [US2] Demonstrate missing/duplicate/changed-row and partial
  three-record inventory RED, then reconcile all three expected witnesses.
- [ ] T254-206 [US2] Generate board parity vectors and register the exact
  compiled board target with M8 authority/replay checks.

## Phase 6 — S254-3 registry and consumer-ready cutover surface

- [ ] T254-301 [US3] Validate the append-only release-label-to-hash registry:
  role/board addresses, predecessor policies, references, sources, scan point.
- [ ] T254-302 [US3] Preserve the committed v0 manifests as immutable
  history and publish the target as a new registry entry, never a replacement.
- [ ] T254-303 [US3] Prepare no-secret migration packages and one-for-one
  dry-run inventory reconciliation without live submission.
- [ ] T254-304 [US3] Prove the consumer example can obtain release/hash, policy,
  outref, and current KEL authority from the family-neutral producer result
  without a single-address assumption.
- [ ] T254-305 [US3] Hand the registry, transaction-derived edges, and simulated
  old/new stream to #171 for follower/query/relayer blindness proof.
- [ ] T254-306 [US3] Document the cutover preflight, temporary v0 liquidity,
  controller/witness package flow, reconciliation format, rollback boundary,
  and explicit no-live-submit limit.

## Verification and acceptance

- [ ] T254-401 Prove every invariant with named RED and permanent GREEN; close
  no BLOCKING campaign row as residual.
- [ ] T254-402 Complete focused onchain/offchain parity, package, registry,
  inventory, and consumer-contract checks plus full repository CI under the
  machine gate and build budget.
- [ ] T254-403 Reconcile the final compiled checkpoint/board identities with
  the M8 registered targets and record both acceptance-time announcements.
- [ ] T254-404 Produce a no-submit v0-to-target dry-run pairing every
  checkpoint and all three board rows with no orphan.
- [ ] T254-405 Obtain the #171 seam acceptance and cutover-readiness proof;
  #254 cannot declare the preproduction event unblocked from producer evidence
  alone.
- [ ] T254-406 Verify task stamps, audited tree, campaign, history, and PR.
- [ ] T254-407 After #253/#171/M8/desk gates, execute the first real cutover;
  carry all inventoried checkpoints and three board rows, retain the raw
  transcript, and prove identity/value/lineage plus attack rejection. No
  rehearsal migration precedes it.

## Ordering

`T254-001..005 -> S254-1 -> S254-R -> S254-E -> S254-2 -> S254-3 -> T254-401..406 -> T254-407`.

S254-1 and S254-2 share protocol types and therefore are not independent.
#253 finalizes the target board schema after the S254-2 contract exists and
before any successor deployment. #171 consumer implementation may proceed
after T254-003/T254-305 but cutover readiness waits for both sides.

## YAGNI demonstration rule

Every retained task traces to `spec.md`'s demonstration table. Without a
concrete attack or exact failed consumer read, cut it by mandate amendment.
