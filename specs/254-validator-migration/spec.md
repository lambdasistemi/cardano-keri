# Feature specification — #254 validator migration

Artifact ceiling: 12,000 bytes and 210 lines.

## Outcome

A deployed checkpoint or endpoint-board record can move from one validator
hash to its approved successor without abandoning identity, authority,
anti-replay state, protected value, or observable history. The preproduction
deployment is the first migration: every live checkpoint and all three live
board records move to the cutover hashes and remain resolvable on both sides
of the atomic migration transaction.

The motivation is stranding only. Migration records transaction context; they
never create KERI identity facts, conviction records, or tombstones.

## User stories

### US1 — a controller carries a checkpoint across a validator upgrade (P1)

The checkpoint's current controller authorizes one exact source-to-target
move. Any relayer may submit it. The successor preserves the projected KEL
state and lifecycle role, and the transaction replaces the old quantity-one
AID token with the same asset name under the successor policy.

### US2 — the live endpoint board crosses the same cutover (P1)

Each existing board owner retires its deployed marker into the successor
family. The successor retains witness identity, endpoint content, lifecycle
owner, and deposit while satisfying the successor datum/authentication rules.
All three public records migrate; a partial catalog is not called a cutover.

### US3 — consumers resolve an AID across releases (P1)

Followers, query services, relayers, and the #166 stranger journey receive a
minimal release-label-to-hash registry rather than one checkpoint address.
They derive migration edges from the transaction that spends the predecessor,
burns its token, mints the successor token, and creates the successor. A
consumer example that mints a CID authorized by the resolved KEL can use the
returned current controller state without a later interface retrofit.

## Design decision

Choose a **hash-identified validator family with migration entry/exit**. Each
successor is applied with its one accepted predecessor policy; its script hash
is release identity and the atomic transaction is the lineage edge. Datum
version and origin fields are forbidden duplication. The immutable v0 bridge
uses its existing `Close`/`Retire` exits. Governance may publish the registry
and schedule cutover, but never authorize an identity move.

Migration changes transaction context, not KEL state. Authorization therefore
uses the source datum's current controller threshold over a domain-separated
migration message binding source policy/outref, target policy/address,
lifecycle role, carried state, and legacy refund address when present. This
follows `close.ak`. A controller signs once; any party may relay the package.

## Requirements

- **RQ-254-01 — hash is release identity:** no datum version exists. Applied
  script/policy hashes identify releases; labels live only in the registry.
- **RQ-254-02 — pinned predecessor spend:** a successor accepts migration only
  when one transaction consumes the named outref under its compile-time
  predecessor policy; caller data cannot choose another predecessor.
- **RQ-254-03 — controller authority:** checkpoint migration signatures use
  the source checkpoint's current keys/threshold; no other key substitutes.
- **RQ-254-04 — permissionless submission:** controller authorization is data,
  not a transaction signer; any relayer may submit the unchanged package.
- **RQ-254-05 — exact checkpoint continuity:** `cesr_aid`, current and next
  keys/thresholds, witnesses, `toad`, checkpoint `seq`, and KERI `native_sn`
  are byte-for-byte unchanged. ACTIVE, ARMED, and FROZEN retain their role;
  ARMED also retains hunter/deadline. No terminal successor is invented.
- **RQ-254-06 — one-for-one asset transition:** the named source token is
  burned once, the successor token is minted once with the same derived asset
  name under the target policy and confined to one successor; no policy extras.
- **RQ-254-07 — value continuity:** the successor carries the source role's
  protected lovelace/assets except policy-token replacement. The v0 bridge may
  refund old lovelace but requires equal same-transaction capitalization.
- **RQ-254-08 — replay resistance:** authorization binds the consumed outref
  and both policy identities. A used authorization, a changed target,
  a changed role/state/refund, or a migration from another duplicate
  projection rejects.
- **RQ-254-09 — durable transaction edge:** the accepted transaction itself
  spends the predecessor, burns its token, mints the same-name successor, and
  creates it. Consumers derive lineage from the event; no origin field exists.
- **RQ-254-10 — legacy checkpoint bridge:** a deployed version-0 ACTIVE
  checkpoint migrates through its existing authorized `Close` plus burn and
  successor entry. Any v0 ARMED/FROZEN row blocks cutover: it has no such exit.
- **RQ-254-11 — future checkpoint path:** every new family member introduced
  supports exact-role out and one compile-time predecessor policy.
- **RQ-254-12 — board parity:** a board successor spends its pinned
  predecessor and preserves witness/content/owner/deposit. The v0 bridge uses
  authorized `Retire`/burn; target authentication includes #253's binding.
- **RQ-254-13 — no partial cutover:** deployment succeeds only when the source
  inventories reconcile one-for-one and all three board witnesses succeed.
- **RQ-254-14 — cross-release consumer surface:** the deployment artifact
  publishes an append-only label-to-hash/policy/address/reference map and
  earliest scan point, with no duplicate on-chain release metadata.
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
| `INV-254-REPLAY` | BLOCKING | Authorization can be reused or redirected to another outref, policy, role, state, target, or refund. | A named binding mutant is rejected by a permanent property. |
| `INV-254-VALUE` | BLOCKING | Source/target tokens or protected escrow can be lost, duplicated, redirected, or multiplied. | Exact burn/mint/confinement and role-value mutants are rejected. |
| `INV-254-LINKAGE` | BLOCKING | Migration succeeds without spending the exact predecessor input accepted by the successor's applied policy parameter. | Wrong-policy, wrong-outref, missing-input, and split-transaction mutants fail; a follower derives the edge from the accepted transaction. |
| `INV-254-BOARD` | BLOCKING | A board row changes witness/content/owner/deposit, bypasses successor authentication, or one of the three live rows is omitted. | Field/authentication/partial-inventory mutants reject and all three successors reconcile. |
| `INV-254-CONSUMER` | BLOCKING | A supported migration becomes invisible or resolves from existence/release recency alone rather than authenticated use. | A simulated old-to-new stream remains visible from both bootstrap sides; ambiguity fails closed. |
| `INV-254-UPLC` | BLOCKING | Compiled UPLC admits an authority or replay bypass hidden by source-level tests, or the proof target changes silently. | M8 kills a named compiled mutant for both classes against the announced target. |

Campaign ledger:
`/tmp/ms-keri-1/e274/cardano-keri-254/evidence/mutation-campaign.md`.
The termination and build budget are fixed in `plan.md`.

## Demonstration burden for every retained requirement

The default is CUT. A security requirement stays only when the table names an
attack transaction that succeeds without it; a consumer requirement stays
only when it names the exact read that fails without it.

| Requirement | Demonstration without the feature |
| --- | --- |
| RQ-254-01 | Consumer read: deployment, follower, relayer, and M8 cannot select or verify a script from a label without the label-to-hash registry; no on-chain datum integer is needed for that read. |
| RQ-254-02 | Attack: submit a genuine signed package while spending a duplicate under an attacker policy; it reaches the trusted successor unless the applied successor pins and observes the real predecessor. |
| RQ-254-03 | Attack: migrate another controller's checkpoint with no current-controller quorum. |
| RQ-254-04 | Consumer action: an unrelated relayer cannot submit the controller's already-signed package if relay identity is part of authority. |
| RQ-254-05 | Attack: change keys, threshold, sequence, AID, witnesses, or lifecycle role during a context-only move and thereby forge KEL state. |
| RQ-254-06 | Attack: burn without mint, mint twice, change the AID asset name, or redirect the successor token. |
| RQ-254-07 | Attack: skim lovelace/admitted assets or create an undercapitalized successor; the audit's empty-output transaction is the minimal witness. |
| RQ-254-08 | Attack: reuse a signed package against a different consumed outref or sign stale state while consuming a newer checkpoint; the audit's `7/4` versus `23/19` transaction is the minimal witness. |
| RQ-254-09 | Consumer read: the follower's block-atomic transaction application cannot associate predecessor spend with successor creation if they are allowed in separate transactions; no stored origin is read. |
| RQ-254-10 | Attack/availability: accept a v0 ARMED/FROZEN row through a Close path the immutable deployed script does not authorize, or silently orphan it during cutover. |
| RQ-254-11 | Attack: a future source burns independently while an unrelated predecessor mints into the successor unless both family arms enforce the same atomic transaction. |
| RQ-254-12 | Attack: change board witness/content/owner/deposit or bypass #253 target authentication during migration. |
| RQ-254-13 | Consumer read: the cutover desk cannot distinguish complete migration from an orphaned checkpoint or missing one of the three board rows without inventory reconciliation. |
| RQ-254-14 | Consumer read: follower address interest, relayer script selection, query decoding, and M8 target selection fail after a hash change if only one current locator is published. |
| RQ-254-15 | Attack: manufacture new controller/KEL facts during migration without a checked KERI event. |
| RQ-254-16 | Consumer read/security control: M8 cannot prove the shipped program rejected authority/replay mutants if the exact applied hash/entrypoint is not registered. |
