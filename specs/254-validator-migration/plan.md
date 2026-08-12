# Implementation plan — #254 validator migration

Artifact ceiling: 14,000 bytes and 260 lines.

## Durable design

Introduce a hash-identified checkpoint and board family. A source program owns
`MigrateOut`; its successor owns `MigrateIn` and is applied with the one
predecessor policy it accepts. Both sides validate the same transaction, exact
continuity, and the same domain-separated current-controller authorization.
The applied script hash is on-chain release identity. The transaction is the
lineage edge. Datums contain neither a version integer nor an origin pointer.
Governance publishes the minimal release-label-to-hash registry and cutover
time but has no identity-migration authority.

The deployed preproduction version 0 predates this protocol. Its immutable
checkpoint already exposes controller-authorized `Close`/`CloseBurn`, and its
board exposes owner-authorized `Retire`/`Burn`. The successor therefore contains
explicit legacy entry checks over those existing exits. The bridge is narrow:
ACTIVE checkpoints only, current board rows only, exact old policy IDs, and
the committed preproduction network. Later versions use the permanent two-
sided family protocol.

## Trade-off record

| Option | Benefit | Cost / rejection |
| --- | --- | --- |
| Dedicated migrate action only | Small new redeemer surface. | Cannot retrofit deployed v0; without a pinned successor it permits target drift and repeats the design at every release. |
| Datum version + origin family | Makes metadata visible without transaction history. | Duplicates script-hash identity and ledger history, has no M1 consumer, and created the audited sync gap. Rejected by NOTE-006. |
| Hash-identified family | Applied successor pins one predecessor policy; atomic transaction is lineage; minimal registry serves off-chain selection. | Requires coordinated checkpoint/board cutover and history-aware consumers. **Chosen.** |
| Governance-gated transition | Easy global scheduling and allowlist. | Central authority can move identity state, contrary to #219 and the projection constitution; controller compromise model becomes operator compromise. Rejected. |

## Authority and anti-replay

The migration authorization is a Cardano-context message, not a KERI event.
It binds network, source policy/outref, target policy/address, source
role, exact carried state, and any legacy refund address. Its signatures are
evaluated against the source checkpoint's current threshold. This preserves
#219's separation: KERI events alone authorize key-state advancement;
current-controller signatures authorize a context-only relocation, and anyone
may submit the signed package.

The ledger's single-spend rule plus exact source burn prevents a second
settlement. The signed outref and target binding prevent one authorization
from being redirected to another duplicate projection or successor family.
The successor's applied predecessor-policy parameter prevents an
attacker-created old policy from minting a trusted successor.

## Legacy cutover shape

### Checkpoints

1. Inventory every live output at all version-0 role addresses from the
   committed deployment point. Require every row to be ACTIVE and uniquely
   decodable under the deployed policy.
2. For each row, obtain the existing v0 `Close` authorization and the new
   migration authorization from the same current controller quorum.
3. In one transaction, spend and burn the v0 token, satisfy the exact v0
   refund, mint and confine the successor token, and create successor state
   with unchanged KEL fields, ACTIVE role, and source lovelace floor. The same
   transaction is the predecessor-to-successor edge.
4. Reconcile old inventory to new inventory one-for-one. The old refund means
   the payer supplies equal temporary lovelace for the new escrow; accepted v0
   checkpoints contain no foreign assets, so no unique non-ADA asset must be
   duplicated.

### Endpoint board

1. Inventory the exact three current records under the frozen board policy.
2. Each old owner authorizes v0 `Retire`/`Burn`; the target record also
   satisfies #253's accepted target-schema witness authorization without
   migration code interpreting or restating that schema.
3. Mint one same-witness-name target marker and preserve the deposit and
   content in the transaction that spends the exact v0 input. Reconcile all
   three witnesses before calling the board cut over.

## Draft cross-seam contract for #171

This is negotiation input to the milestone desk, not a direct ruling on the
consumer epic.

### Version registry

Replace the singular deployment locator with a minimal ordered registry
containing:

- registry schema version and earliest scan slot/block;
- for each checkpoint release label: applied script hash, policy ID,
  ACTIVE/ARMED/FROZEN addresses, accepted predecessor policy, and reference
  scripts;
- for each board release label: applied hash, policy/address, accepted
  predecessor policy, and reference script;
- cutover status (`prepared`, `open`, or `complete`) without deleting prior
  entries.

Checkpoint and board datums remain their role/schema state only. They do not
carry registry labels, validator versions, or migration origins. ARMED retains
hunter/deadline. The board successor uses the schema selected by #253 without
a generic migration envelope.

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
  expose release label, applied hash/policy, role, outref, and decoded KEL
  state.
- Candidates group by AID. Valid ordinary spends and atomic migration
  transactions form lineage edges. Resolution prefers the candidate demonstrating
  greatest authenticated use (`seq`, then `native_sn`) along a valid lineage;
  a registry label alone never wins. A tie without a unique used lineage is an
  explicit ambiguity.
- Unknown hashes/labels, incomplete migration transactions, gaps in a derived
  edge, or policy-to-registry mismatch are errors. They never collapse to “not
  found.”
- Board lookup applies the analogous witness-key lineage and the target
  release's authentication rules; malformed old/new rows fail the whole
  catalog closed.

### Relayer and #166

- The relayer receives the resolved release/hash/policy/outref and selects the
  matching family scripts; it refuses a hash outside the registry rather
  than falling back to the newest manifest.
- The consumer example receives a family-neutral resolved checkpoint whose
  current keys and threshold can authorize a CID mint. No consumer derives
  authority from policy/release metadata.
- The #166 stranger transcript crosses or starts after the cutover using the
  same registry and records the source/migration/successor identities it
  actually observed.

## Dependency map

| Dependency | Direction and condition |
| --- | --- |
| `origin/main` constitution and PR template | Rebase before implementation. Seed `03ca794` is based on `6e2bd82`, before constitution merge `a716f4b` and template merge `35970a6`; planning reads those main artifacts now, but no behavior campaign starts on the stale base. |
| #219 permissionless advance | Predecessor authority model. Migration must not alter its KEL-event authorization or eq5/AE anti-replay mechanism. |
| #271 payee authentication | The epic ruling inserts S254-E after S254-1 and before S254-2. S254-E adopts the revised standalone entitlement component from #271 (`03da8a72e3a58d63ca4268bdfd6157e41a7ebf33`, manifest `03ad05e8a32c97b9ee456beb698a4e93b9974d1ba2b0607bc83cada054586895`, PR #278), superseding `1e3e767`, and owns its family-coupled integration without restating or revising #271's internal authorization schema. Its sole remaining build audits the revised lifecycle and integration together on #271's separate ledger, and the #271 owner reviews its submission through the epic owner. #163/#164 stay blocked until the entitlement ships. |
| #253 board hardening | Rides the family. #253 owns the accepted authentication schema of the not-yet-deployed target board release; #254 supplies only the atomic migration vehicle and may not enumerate or weaken that schema. The first deployment contains both migration entry and #253 semantics; no intermediate unhardened target is deployed. NOTE-006 changes DEP-253-254: script hash identifies the release and the transaction is the edge; route the revised contract through the epic owner before S254-2. |
| #171 consumer halves | Desk-negotiated implementation of multi-release follower/query/relayer semantics and #253 board verification. Must land before cutover opens. |
| Preproduction cutover | First real migration consumer. Requires producer and #171 consumer changes, reference publication, inventory reconciliation, controller/witness authorizations, and an approved live-operation plan. |
| e171 consumer example / #166 | Must consume the family-neutral resolved result and demonstrate no address/policy retrofit. Runs after cutover readiness. |
| M8 Blaster | Compile-target and property dependency. New hashes/entrypoints are registered at acceptance and cutover; authority/replay proof target cannot move silently. |

## Planned implementation slices

No slice starts while the machine build gate is closed.

### S254-1 — shared authorization and checkpoint migration family

- Remove the superseded version/origin datum types and retain only the
  demonstrated migration-authorization parity fields.
- Apply the successor with one accepted predecessor policy; add permanent
  migrate-out/in checks and the exact preproduction v0 ACTIVE
  bridge.
- Extend deployment manifest/build-package surfaces without removing v0.
- Ship RED controls for authority, redirect/replay, identity, role, asset, and
  value classes; generated Haskell/Aiken vectors remain one source.

### S254-E — enforcement entitlement integration

- Adopt, rather than recreate, the seven revised #271 standalone component
  sources byte-identically from `03da8a72e3a58d63ca4268bdfd6157e41a7ebf33`
  under manifest `03ad05e8a32c97b9ee456beb698a4e93b9974d1ba2b0607bc83cada054586895`.
- Supply the component's finite lifetime as an explicit release parameter and
  retain its demonstrated 5,000,000-lovelace concurrent-capital floor; no
  standalone 10,000-slot default is recreated downstream.
- Integrate reveal consumption through ArmedV2 and the Freeze/Convict payout
  branches under the complete #271 mandate and invariant set.
- Charge the one combined revised-lifecycle plus family-integration audit as
  build 3/3 on #271's ledger; require the #271 design-owner review through the
  epic owner before ticket-owner acceptance.
- Do not begin until S254-1 is accepted and pushed.

### S254-2 — endpoint-board parity and #253 handoff

- Add hash/policy-pinned board migrate-out/in checks plus the frozen
  v0 Retire bridge.
- Bind the target-schema hook so #253's accepted authentication runs unchanged
  before target deployment; #254 does not own its internal fields.
- Prove one-for-one three-record inventory and reject field/authentication/
  deposit mutants.

### S254-3 — release registry and reproducible cutover tooling

- Publish the minimal release-label-to-hash registry and exact source/reference
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

Budget: **8 building audits** for #254's rows after the charged A-005 extension,
currently `builds_spent=6` and `builds_budget=8`; all six remain on the record.
Owner development builds are separately controlled. S254-E instead charges
the distinct #271 ledger at 2/3 with build 3/3 reserved for its combined
revised-lifecycle plus family-integration audit; neither ledger may borrow from
the other.

1. Builds 1–5: spent on S254-1A, the superseded S254-1B design/audits, and its
   first parity repairs; all evidence remains retained.
2. Build 6/8: spent on the accepted structural full-address S254-1 repair.
3. Build 7/8: reserved for the first independent audit of S254-2.
4. Build 8/8: reserved for the first independent audit of S254-3.

Any blocking finding that requires another repair submission is a fresh
overrun and requires an itemized epic ruling.

Reading, typecheck-only, and interpreted mutation work that compiles nothing is
unmetered. A build cannot begin while the machine gate is closed or if it would
breach the machine disk floor.

Each row begins OPEN. `KILLED` requires a named mutant shown RED and a permanent
check that kills its class. Because every row is BLOCKING, none may terminate
as RESIDUAL. A row may become BLOCKED only with the exact external fact named.
The campaign closes at set-point only when every row is terminal. A quiet tail
round never closes over an OPEN row; budget exhaustion with an OPEN row records
campaign overrun and escalates rather than accepting silence.
