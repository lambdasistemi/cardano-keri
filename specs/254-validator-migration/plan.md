# Implementation plan — #254 validator-version migration

Artifact ceiling: 14,000 bytes and 260 lines.

## Durable design

Introduce a version-parameterized checkpoint and board family. A normal
version N program owns `MigrateOut`; version N+1 owns `MigrateIn` and pins N's
policy/version. Both sides validate one transaction, exact continuity, and the
same domain-separated current-controller authorization. Governance publishes
the registry and cutover time but has no identity-migration authority.

The deployed preproduction version 0 predates this protocol. Its immutable
checkpoint already exposes controller-authorized `Close`/`CloseBurn`, and its
board exposes owner-authorized `Retire`/`Burn`. Version 1 therefore contains
explicit legacy entry checks over those existing exits. The bridge is narrow:
ACTIVE checkpoints only, current board rows only, exact old policy IDs, and
the committed preproduction network. Later versions use the permanent two-
sided family protocol.

## Trade-off record

| Option | Benefit | Cost / rejection |
| --- | --- | --- |
| Dedicated migrate action only | Small new redeemer surface. | Cannot retrofit deployed v0; without a pinned family it permits target/version drift and repeats the design at every release. |
| Version-parameterized family | Checked version marker, pinned predecessor, uniform later upgrades, explicit legacy bridge, consumer registry. | More datum/manifest/parity surface and a coordinated checkpoint/board cutover. **Chosen.** |
| Governance-gated transition | Easy global scheduling and allowlist. | Central authority can move identity state, contrary to #219 and the projection constitution; controller compromise model becomes operator compromise. Rejected. |

## Authority and anti-replay

The migration authorization is a Cardano-context message, not a KERI event.
It binds network, source version/policy/outref, target version/policy, source
role, exact carried state, and any legacy refund address. Its signatures are
evaluated against the source checkpoint's current threshold. This preserves
#219's separation: KERI events alone authorize key-state advancement;
current-controller signatures authorize a context-only relocation, and anyone
may submit the signed package.

The ledger's single-spend rule plus exact source burn prevents a second
settlement. The signed outref and target binding prevent one authorization
from being redirected to another duplicate projection or successor family.
The successor's pinned predecessor prevents an attacker-created old policy
from minting a trusted successor.

## Legacy cutover shape

### Checkpoints

1. Inventory every live output at all version-0 role addresses from the
   committed deployment point. Require every row to be ACTIVE and uniquely
   decodable under the deployed policy.
2. For each row, obtain the existing v0 `Close` authorization and the new
   migration authorization from the same current controller quorum.
3. In one transaction, spend and burn the v0 token, satisfy the exact v0
   refund, mint and confine the v1 token, and create the v1 state with unchanged
   KEL fields, ACTIVE role, source lovelace floor, and an origin naming the v0
   input.
4. Reconcile old inventory to new inventory one-for-one. The old refund means
   the payer supplies equal temporary lovelace for the new escrow; accepted v0
   checkpoints contain no foreign assets, so no unique non-ADA asset must be
   duplicated.

### Endpoint board

1. Inventory the exact three current records under the frozen board policy.
2. Each old owner authorizes v0 `Retire`/`Burn`; the target record also
   satisfies the target schema's witness authorization. For #253's target,
   that signature binds owner and monotonic sequence as well as endpoint.
3. Mint one same-witness-name target marker, preserve the deposit and content,
   and record the exact v0 input origin. Reconcile all three witnesses before
   calling the board cut over.

## Draft cross-seam contract for #171

This is negotiation input to the milestone desk, not a direct ruling on the
consumer epic.

### Version registry

Replace the singular deployment locator with an ordered registry containing:

- registry schema version and earliest scan slot/block;
- for each checkpoint validator version: non-negative version, policy ID,
  ACTIVE/ARMED/FROZEN addresses, predecessor version/policy, and reference
  scripts;
- for each board version: version, policy/address, predecessor edge, and
  reference script;
- cutover status (`prepared`, `open`, or `complete`) without deleting prior
  entries.

The checkpoint datum marker is `CheckpointDatumV2 { validator_version,
migration_origin, state }`, where `state` is the unchanged V1 KEL projection
and `migration_origin` is absent for native registration or contains immediate
source version/policy/outref. ARMED wraps that versioned checkpoint and retains
hunter/deadline. The board successor uses the same version/origin envelope
around the board schema selected by #253.

### Follower semantics

- Interest is the union of every supported checkpoint role address and board
  address, plus unrelated funding addresses. It is constructed from the full
  registry, never one current manifest entry.
- A fresh follower starts no later than the earliest registered deployment so
  it observes source rows and migration transactions. Applying a migration
  and its derived edge is block-atomic and rollback-exact.
- Missing one side of a simulated migration is a failing signal, not an empty
  successful result.

### Query and resolution semantics

- Query inputs select a registry, not one `(policy,address)` pair. Results
  expose validator version, policy, role, outref, origin, and decoded KEL
  state.
- Candidates group by AID. Valid same-version spends and exact migration
  origins form lineage edges. Resolution prefers the candidate demonstrating
  greatest authenticated use (`seq`, then `native_sn`) along a valid lineage;
  a version number alone never wins. A tie without a unique used lineage is an
  explicit ambiguity.
- Unknown versions, malformed origins, gaps in a claimed edge, or policy-to-
  registry mismatch are errors. They never collapse to “not found.”
- Board lookup applies the analogous witness-key lineage and the target
  version's authentication rules; malformed old/new rows fail the whole
  catalog closed.

### Relayer and #166

- The relayer receives the resolved version/policy/outref and selects the
  matching family scripts; it refuses a version outside the registry rather
  than falling back to the newest manifest.
- The consumer example receives a family-neutral resolved checkpoint whose
  current keys and threshold can authorize a CID mint. No consumer derives
  authority from policy/version metadata.
- The #166 stranger transcript crosses or starts after the cutover using the
  same registry and records the source/migration/successor identities it
  actually observed.

## Dependency map

| Dependency | Direction and condition |
| --- | --- |
| `origin/main` constitution and PR template | Rebase before implementation. Seed `03ca794` is based on `6e2bd82`, before constitution merge `a716f4b` and template merge `35970a6`; planning reads those main artifacts now, but no behavior campaign starts on the stale base. |
| #219 permissionless advance | Predecessor authority model. Migration must not alter its KEL-event authorization or eq5/AE anti-replay mechanism. |
| #271 payee authentication | Recommend batching into #254 because migration changes the checkpoint spend dispatch and role/value branches that contain Freeze/Convict payouts; #253 touches only the board. Require hunter/convictor payee key hashes in `extra_signatories`, with substituted-payee RED, before #163/#164. Epic ruling required before the implementation fence freezes. |
| #253 board hardening | Rides the family. It finalizes the not-yet-deployed target board version by adding owner+sequence witness binding; the first deployment of that version contains both migration entry and #253 semantics. Do not deploy an intermediate unhardened target. |
| #171 consumer halves | Desk-negotiated implementation of multi-version follower/query/relayer semantics and #253 board verification. Must land before cutover opens. |
| Preproduction cutover | First real migration consumer. Requires producer and #171 consumer changes, reference publication, inventory reconciliation, controller/witness authorizations, and an approved live-operation plan. |
| e171 consumer example / #166 | Must consume the family-neutral resolved result and demonstrate no address/policy retrofit. Runs after cutover readiness. |
| M8 Blaster | Compile-target and property dependency. New hashes/entrypoints are registered at acceptance and cutover; authority/replay proof target cannot move silently. |

## Planned implementation slices

No slice starts while the machine build gate is closed.

### S254-1 — shared version and checkpoint migration family

- Add the version/origin and migration-authorization parity types.
- Add permanent v1 migrate-out/in checks and the exact preproduction v0 ACTIVE
  bridge.
- Extend deployment manifest/build-package surfaces without removing v0.
- Ship RED controls for authority, redirect/replay, identity, role, asset, and
  value classes; generated Haskell/Aiken vectors remain one source.
- If the epic accepts the #271 recommendation, include its checkpoint payee
  signer properties here because the same dispatch/value surface is changed.

### S254-2 — endpoint-board parity and #253 handoff

- Add board version/origin and permanent migrate-out/in checks plus the frozen
  v0 Retire bridge.
- Bind the target-schema hook so #253 finalizes witness owner+sequence
  authentication before target deployment.
- Prove one-for-one three-record inventory and reject field/authentication/
  deposit mutants.

### S254-3 — release registry and reproducible cutover tooling

- Publish the multi-version registry schema and exact source/reference
  identities while preserving historical entries.
- Build inventory/reconciliation and transaction-package tooling that can
  execute the desk-gated cutover after every dependency is accepted. No live
  action occurs during mandate work, and no earlier rehearsal migration makes
  the cutover cease to be the first real event.
- Provide the desk with the final producer contract/hash for #171 negotiation
  and M8 target registration.

## Path and authority fences

Expected implementation surface is limited to the checkpoint/board Aiken
family and generated vectors, their Haskell parity/deployment mirrors,
deployment manifest/transaction packages, focused proofs, docs, and this spec
directory. Exact files are frozen after rebase and #271 ruling.

Forbidden without a revised contract:

- #171 follower/query/backend implementation;
- live preproduction transactions, signing, submission, or manifest overwrite
  before an explicit desk cutover release and all dependency barriers;
- KERI event semantics, registration/advance authorization, tombstone state,
  governance keys, dependency/lock changes, CI workflows, or unrelated MPFS
  migration code;
- edits to committed historical acceptance transcripts.

## Verification campaign and stopping rule

Campaign ledger:
`/tmp/ms-keri-1/e274/cardano-keri-254/evidence/mutation-campaign.md`.

Budget: **3 building audits**, initially `builds_spent=0` and
`builds_budget=3`. Owner development builds are separately controlled and do
not spend this audit budget.

1. Build 1: fresh audit of the first complete candidate; establish one warm
   tree and attack all eight declared rows with named source/value/signature
   mutants.
2. Build 2: reserved for the one permitted repaired candidate and fresh audit;
   unused if submission 1 settles every row.
3. Build 3: contingency for an epic-authorized fresh campaign or compiled-UPLC
   discrepancy. It is not automatic permission for a third submission.

Reading, typecheck-only, and interpreted mutation work that compiles nothing is
unmetered. A build cannot begin while the machine gate is closed or if it would
breach the machine disk floor.

Each row begins OPEN. `KILLED` requires a named mutant shown RED and a permanent
check that kills its class. Because every row is BLOCKING, none may terminate
as RESIDUAL. A row may become BLOCKED only with the exact external fact named.
The campaign closes at set-point only when every row is terminal. A quiet tail
round never closes over an OPEN row; budget exhaustion with an OPEN row records
campaign overrun and escalates rather than accepting silence.

## Artifact measurements

Measured after authoring and before mandate submission. The compiled six-file
packet ceiling is 60,000 bytes and 1,200 lines.

| Artifact | Bytes | Lines | Ceiling |
| --- | ---: | ---: | --- |
| `spec.md` | 11,454 | 185 | 12,000 / 210 |
| `plan.md` | 13,198 | 243 | 14,000 / 260 |
| `modules-model.md` | 8,054 | 157 | 9,000 / 180 |
| `data-model.md` | 7,490 | 192 | 8,000 / 210 |
| `functions-model.md` | 9,067 | 176 | 10,000 / 200 |
| `tasks.md` | 6,513 | 116 | 7,000 / 160 |
| **Total** | **55,776** | **1,069** | **60,000 / 1,200** |
