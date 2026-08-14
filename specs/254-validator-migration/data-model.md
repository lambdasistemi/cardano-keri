# Data model — #254 validator migration

Artifact ceiling: 8,000 bytes and 210 lines.

## `DAT-254-RELEASE` — off-chain release identity

- `label`: human-readable, unique only within the release registry;
- `script_hash`, `policy_id`, role addresses, and reference identity;
- `accepted_predecessor_policy: Option<PolicyId>`.

The applied hash is on-chain identity. The label is deployment metadata and is
never serialized into checkpoint/board datum or redeemer state. It never
substitutes for checkpoint `seq` or KERI `native_sn`.

## `DAT-254-PREDECESSOR` — applied successor parameter

- `accepted_policy: PolicyId`

Validation:

- compiled/applied into each successor validator, never caller-selected;
- migrate-in observes an input at `source_ref` under `accepted_policy`;
- the same transaction burns that predecessor token, mints the successor, and
  creates the exact successor output;
- nothing is stored in the successor datum: the accepted transaction is the
  predecessor edge.

## `DAT-254-TARGET` — authorized successor identity

- `target_policy: PolicyId`
- `target_role: CheckpointRole | BoardRole`
- `target_address: Address`
- `legacy_refund_address: Option<Address>`

The policy/address/role tuple is checked against the applied family.
The refund is present only when an immutable legacy exit requires it.

## `DAT-254-AUTHORIZATION` — checkpoint migration package

- `domain`: new frozen versioned protocol identifier;
- `network_id`;
- `source_policy`, `source_ref`;
- complete `target: DAT-254-TARGET`;
- exact source lifecycle role;
- exact carried checkpoint projection and role payload;
- `controller_signatures: [(key_index, signature)]`.

The canonical message excludes no caller-controlled field that can redirect
identity, value, or successor selection. Signatures are evaluated against the
source checkpoint's current keys/threshold. Duplicate indices never increase
quorum.

## `DAT-254-CHECKPOINT` — carried checkpoint state

The successor uses the existing checkpoint role datum shape; it adds no
generic version/origin envelope. Migration preserves exactly:

- AID;
- current keys and threshold;
- next-key digests and threshold;
- witnesses and `toad`;
- Cardano checkpoint `seq` and KERI `native_sn`.

Native registration and ordinary lifecycle transitions therefore need no
migration-specific metadata path. Advance may change only fields authenticated
by its KERI rotation. Migration retains every KEL projection field.

## `DAT-254-ARMED` — in-flight challenge

- `checkpoint: CheckpointDatumV1`
- `hunter_pkh`
- `deadline`

Migration preserves all three fields and the ARMED role. FROZEN preserves the
checkpoint and FROZEN role. Version-0 ARMED/FROZEN have no legacy
exit and therefore block the first cutover rather than being rewritten.

## `DAT-254-CHECKPOINT-TRANSITION`

Relationships:

- consumes exactly one source checkpoint identified by
  `(source_policy, derived_aid_asset_name, source_ref)`;
- burns exactly that token under source policy;
- mints exactly one token with the same asset name under target policy;
- creates exactly one target-role output containing the unchanged role datum
  and the target token;
- carries the source role's exact protected value, subject only to the
  documented legacy refund/re-capitalization shape.

## `DAT-254-BOARD` — board successor record

The successor uses `BoardDatumForRelease`, with no generic version or origin
envelope.

Continuity fields across migration are witness key, endpoint content,
lifecycle owner key hash, and protected deposit. The board successor uses
#253's accepted target schema (owner plus consumed-nonce witness
authorization; no sequence field and no version-only constructor under the
routed DEP contract). #254 owns only the atomic-migration vehicle, not the
board's internal authentication fields, and generic migration metadata cannot
waive the target-schema check.

## `DAT-254-BOARD-TRANSITION`

Relationships:

- consumes one source marker named by witness key and burns it once;
- mints one same-name target marker and confines it to one successor;
- requires the source board owner's authorization and the target schema's
  witness authorization;
- preserves source deposit and continuity fields;
- spends the exact predecessor input accepted by the successor's applied
  policy parameter in the same transaction.

The v0 bridge uses the frozen policy and existing `Retire`/`Burn`; later
releases use the permanent family migration actions.

## `DAT-254-REGISTRY` — validator-family registry

- `schema_version`
- `network`
- `earliest_scan_point: (slot, block_hash)`
- `checkpoint_releases: NonEmpty<CheckpointReleaseEntry>`
- `board_releases: NonEmpty<BoardReleaseEntry>`
- `cutover_status`

Each checkpoint entry contains a release label, applied hash, policy,
ACTIVE/ARMED/FROZEN addresses, accepted predecessor policy when any,
script/reference identities, and source commit. Each board entry contains the
analogous label, applied hash, policy/address, accepted predecessor policy,
reference, and source identity.

Validation:

- labels and hashes are unique; accepted-predecessor policies name an earlier
  entry when the predecessor is supported;
- policy/address/reference identities are exact and non-empty;
- historical entries are append-only;
- earliest scan point is not later than any registered deployment;
- a complete cutover names both old and new entries rather than deleting old.

## `DAT-254-PACKAGE` — reproducible migration authorization package

- source registry digest and entry;
- source outref, role, value, decoded state;
- target registry digest and entry;
- canonical authorization message bytes;
- indexed controller signatures;
- legacy close/refund package when version 0;
- no secret key material.

Changing the source UTxO, target family, role/state/value, or refund invalidates
the package.

## `DAT-254-INVENTORY` and `DAT-254-RECONCILIATION`

Inventory rows identify every discovered source checkpoint/board row by
release label/hash, policy, role, outref, asset name, datum digest, and value digest.
Reconciliation pairs each source with exactly one settled successor and records
the migration transaction plus successor outref/digests.

Cutover completeness requires:

- no unpaired source or successor;
- no source paired twice;
- every source checkpoint ACTIVE for the v0 bridge;
- exactly the three expected board witness keys represented once each;
- consumer observation of both the source spend and successor creation.

## State transitions

- `Native(hash A) -> Migrate(hash B)` only when B is applied with A's policy.
- `Migrate/Native -> Advance` uses the ordinary KEL-authenticated state shape.
- `ACTIVE -> ARMED -> ACTIVE/FROZEN` carries no migration metadata.
- `ACTIVE|ARMED|FROZEN(source) -> same role(successor)` through migration.
- `ACTIVE(v0) -> ACTIVE(successor)` through the legacy checkpoint bridge only.
- `Board(v0) -> Board(successor)` through legacy Retire/Burn plus target entry.
- Any terminal burn has no migration successor and creates no identity datum.

## Data invariants

- `DATA-INV-254-01`: applied hash/policy identifies the family; the accepted
  predecessor is a program parameter, never datum/redeemer state.
- `DATA-INV-254-02`: migration preserves all KEL projection fields exactly.
- `DATA-INV-254-03`: source and target asset maps are exact singleton policy
  transitions with one confined successor.
- `DATA-INV-254-04`: role payload and protected value survive migration.
- `DATA-INV-254-05`: board continuity cannot bypass target authentication.
- `DATA-INV-254-06`: registry history plus atomic migration transactions remain
  sufficient for old/new bootstrap and rollback.
