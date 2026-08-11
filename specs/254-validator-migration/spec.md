# Feature specification — #254 validator-version migration

Artifact ceiling: 12,000 bytes and 210 lines.

## Outcome

A deployed checkpoint or endpoint-board record can move from validator version
N to the approved N+1 family without abandoning its identity, authority,
anti-replay state, protected value, or observable history. The preproduction
version-0 deployment is the first migration: every live checkpoint and all
three live board records move to the cutover family and remain resolvable on
both sides of the transaction.

The motivation is stranding only. Migration records transaction context; they
never create KERI identity facts, conviction records, or tombstones.

## User stories

### US1 — a controller carries a checkpoint across a validator upgrade (P1)

The checkpoint's current controller authorizes one exact source-to-target
move. Any relayer may submit it. The successor preserves the projected KEL
state and lifecycle role, and the transaction replaces the old quantity-one
AID token with the same asset name under the successor policy.

### US2 — the live endpoint board crosses the same cutover (P1)

Each existing board owner retires its version-0 marker into the version-1
family. The successor retains witness identity, endpoint content, lifecycle
owner, and deposit while satisfying the successor datum/authentication rules.
All three public records migrate; a partial catalog is not called a cutover.

### US3 — consumers resolve an AID across versions (P1)

Followers, query services, relayers, and the #166 stranger journey receive a
version registry and explicit migration edges rather than one checkpoint
address. A consumer example that mints a CID authorized by the resolved KEL
can use the returned current controller state without a later interface
retrofit.

## Design decision

Choose a **version-parameterized validator family with explicit migration
entry and exit actions**.

- A bare dedicated action is insufficient for the first cutover: the deployed
  version-0 scripts are immutable and do not contain it. The successor must
  also understand the existing, already-authorized `Close` and `Retire`
  exits.
- A family gives every applied program a checked version, pins the permitted
  predecessor at the successor, and makes later N to N+1 transitions the same
  protocol rather than another retrofit.
- A governance-gated redeploy is rejected. Governance may publish the version
  registry and schedule a cutover, but it cannot authorize an identity move or
  choose new controller state. That would replace the #219 authority model
  with an operator key.

Migration changes transaction context, not KEL state. Authorization therefore
uses the source datum's current controller threshold over a domain-separated
migration message binding source version/policy/outref, target
version/policy, lifecycle role, carried state, and legacy refund address when
present. This follows `close.ak`'s context-binding pattern. A controller signs
once and any party may relay the complete authorization.

Two checks fix the design boundary now:

1. **Consumer example:** the resolved checkpoint result includes version,
   policy, outref, and unchanged current KEL keys/threshold, so “mint a CID
   signed by a KEL” consumes the family-neutral result directly.
2. **First real event:** the cutover transcript starts from the committed
   version-0 checkpoint and board manifests, migrates every discovered live
   checkpoint plus the three-record board, and proves no source identity or
   record was orphaned.

## Requirements

- **RQ-254-01 — version is enforced:** every successor datum carries a
  non-negative validator version equal to the applied program's version. A
  caller cannot claim a different version in datum or redeemer data.
- **RQ-254-02 — pinned edge:** a successor accepts migration only from its
  applied predecessor version and policy. The target version is exactly source
  version plus one.
- **RQ-254-03 — controller authority:** checkpoint migration signatures are
  checked against the source checkpoint's current keys and threshold. No
  governance, payment, or relayer key substitutes for that quorum.
- **RQ-254-04 — permissionless submission:** controller authorization is data,
  not a required transaction signer; an unrelated relayer can submit it
  without changing the authorized source, target, role, state, or refund.
- **RQ-254-05 — exact checkpoint continuity:** `cesr_aid`, current and next
  keys/thresholds, witnesses, `toad`, checkpoint `seq`, and KERI `native_sn`
  are byte-for-byte unchanged. ACTIVE, ARMED, and FROZEN retain their role;
  ARMED also retains hunter/deadline. No terminal successor is invented.
- **RQ-254-06 — one-for-one asset transition:** the named source token is
  burned once, the successor token is minted once with the same derived asset
  name under the target policy, and it is confined to the one exact successor
  output. No source or target policy extras are admitted.
- **RQ-254-07 — value continuity:** the successor carries the source role's
  complete protected lovelace and admitted assets, with only the policy-token
  replacement. The legacy version-0 bridge may refund the old lovelace through
  its existing exit and require equal successor capitalization in the same
  transaction; the transcript states that temporary liquidity cost honestly.
- **RQ-254-08 — replay resistance:** authorization binds the consumed outref
  and both policy/version identities. A used authorization, a changed target,
  a changed role/state/refund, or a migration from another duplicate
  projection rejects.
- **RQ-254-09 — durable audit edge:** every migrated successor carries a
  `MigrationOrigin` naming source version, source policy, and source outref.
  Ordinary same-version transitions retain that origin; the next migration
  replaces it with the new immediate predecessor, yielding a traversable
  ledger lineage.
- **RQ-254-10 — legacy checkpoint bridge:** a deployed version-0 ACTIVE
  checkpoint migrates atomically through its existing controller-authorized
  `Close` plus token burn and the successor's migration entry. Cutover
  preflight must prove every version-0 checkpoint is ACTIVE; any ARMED or
  FROZEN version-0 checkpoint blocks the cutover because its immutable script
  has no authorized exit.
- **RQ-254-11 — future checkpoint path:** every family version introduced by
  this change supports exact-role migration out and pinned-predecessor
  migration in, so the legacy bridge is not repeated at version 1.
- **RQ-254-12 — board parity:** a versioned board successor binds its
  predecessor edge and preserves witness key, endpoint content, owner, and
  deposit. The version-0 bridge uses existing owner-authorized `Retire` and
  burn; the successor requires whatever new witness authorization its schema
  declares, including #253's owner-and-sequence binding.
- **RQ-254-13 — no partial cutover:** deployment succeeds only when the source
  inventory and successor inventory reconcile one-for-one and the three known
  board witnesses all have successors. Missing, duplicated, or ambiguous rows
  fail the cutover.
- **RQ-254-14 — cross-version consumer surface:** the deployment artifact
  publishes an ordered registry of supported checkpoint and board versions,
  their policies/role addresses, predecessor edges, references, and earliest
  scan point. It never replaces the old entry with a single new address.
- **RQ-254-15 — constitutional projection:** migration may bind transaction
  context and copy KEL-derived state, but may not originate or alter an
  identity-state field without a checked KERI event.
- **RQ-254-16 — compiled boundary:** M8 Blaster continues to target the exact
  compiled checkpoint/board family and demonstrates authority and replay
  mutants can fail. Any new applied-program hash is announced at #254
  acceptance and again at cutover.

## Declared invariant rows

All rows are BLOCKING because their values reach chain state, money, or a
signature. Initial state is OPEN; passing examples alone do not close a row.

| Invariant | Severity | Failure meaning | Success meaning |
| --- | --- | --- | --- |
| `INV-254-IDENTITY` | BLOCKING | Any projected KEL field or live role changes during migration. | A named field/role mutant is rejected and the exact source state is retained. |
| `INV-254-AUTHORITY` | BLOCKING | Migration lands without the source current-controller quorum, or governance/relayer authority substitutes for it. | A missing, foreign, or below-threshold controller authorization is rejected; the same authorization is relayable. |
| `INV-254-REPLAY` | BLOCKING | Authorization can be reused or redirected to another outref, version, policy, role, state, or refund. | A named binding mutant is rejected by a permanent property. |
| `INV-254-VALUE` | BLOCKING | Source/target tokens or protected escrow can be lost, duplicated, redirected, or multiplied. | Exact burn/mint/confinement and role-value mutants are rejected. |
| `INV-254-LINKAGE` | BLOCKING | Datum version disagrees with the applied family or the origin does not name the actual predecessor. | Version/origin mutants fail and a consumer can traverse the on-chain edge. |
| `INV-254-BOARD` | BLOCKING | A board row changes witness/content/owner/deposit, bypasses successor authentication, or one of the three live rows is omitted. | Field/authentication/partial-inventory mutants reject and all three successors reconcile. |
| `INV-254-CONSUMER` | BLOCKING | A supported migration becomes invisible or resolves from existence/version alone rather than authenticated use. | A simulated old-to-new stream remains visible from both bootstrap sides; ambiguity fails closed. |
| `INV-254-UPLC` | BLOCKING | Compiled UPLC admits an authority or replay bypass hidden by source-level tests, or the proof target changes silently. | M8 kills a named compiled mutant for both classes against the announced target. |

Campaign ledger:
`/tmp/ms-keri-1/e274/cardano-keri-254/evidence/mutation-campaign.md`.
The termination and build budget are fixed in `plan.md`.

## Rejection and edge behavior

- Unknown versions, skipped edges, wrong predecessor policies, multiple target
  outputs, foreign datum constructors, malformed origin fields, and ambiguous
  consumer tips fail closed.
- A duplicate projection is not called a forgery. Resolution prefers
  authenticated use (`seq`/`native_sn` and valid lineage), never mere existence
  or the numerically highest validator version; unresolved ties remain
  explicit ambiguity.
- Version-0 ACTIVE checkpoints and board rows need temporary lovelace because
  their existing exit refunds the old deposit while the successor must be
  capitalized. This is a cutover cost, not value continuity evidence.

## Non-goals

- No live transaction, deployment, manifest replacement, or cutover occurs in
  the current mandate phase. The eventual preproduction event remains
  desk-gated acceptance work after producer, #253, #171, and M8 readiness; it
  is not replaced by a rehearsal that would cease to make the cutover the
  first real migration.
- No consumer-side #171 code is owned here; `plan.md` supplies a draft contract
  for desk-mediated negotiation.
- No #253 endpoint-authentication or #271 payee-authentication ruling is
  silently absorbed. Their dependency and batching recommendation are explicit
  in `plan.md`.
