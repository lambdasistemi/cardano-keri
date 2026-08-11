# Data model — #254 validator-version migration

Artifact ceiling: 8,000 bytes and 210 lines.

## `DAT-254-VERSION` — validator version

- Field: `value`, non-negative integer.
- Applied-program invariant: datum/source/target version equals the validator's
  applied version parameter where that program owns the state.
- Transition invariant: target is exactly source plus one.

This is deployment protocol metadata, not KERI sequence state. It never
substitutes for checkpoint `seq` or KERI `native_sn`.

## `DAT-254-ORIGIN` — immediate migration predecessor

- `source_version: ValidatorVersion`
- `source_policy: PolicyId`
- `source_ref: OutputReference`

Validation:

- absent for a checkpoint/board row natively created in its current family;
- present for migration, byte-identical to the transaction's consumed source;
- source version/policy equal the target family's pinned predecessor;
- retained across same-version lifecycle transitions;
- replaced only by the next successful version migration.

## `DAT-254-TARGET` — authorized successor identity

- `target_version: ValidatorVersion`
- `target_policy: PolicyId`
- `target_role: CheckpointRole | BoardRole`
- `target_address: Address`
- `legacy_refund_address: Option<Address>`

The policy/version/address/role tuple is checked against the applied family.
The refund is present only when an immutable legacy exit requires it.

## `DAT-254-AUTHORIZATION` — checkpoint migration package

- `domain`: new frozen versioned protocol identifier;
- `network_id`;
- `source_version`, `source_policy`, `source_ref`;
- complete `target: DAT-254-TARGET`;
- exact source lifecycle role;
- exact carried checkpoint projection and role payload;
- `controller_signatures: [(key_index, signature)]`.

The canonical message excludes no caller-controlled field that can redirect
identity, value, or successor selection. Signatures are evaluated against the
source checkpoint's current keys/threshold. Duplicate indices never increase
quorum.

## `DAT-254-CHECKPOINT` — versioned checkpoint state

- `validator_version: DAT-254-VERSION`
- `migration_origin: Option<DAT-254-ORIGIN>`
- `state: CheckpointDatumV1`

`state` preserves exactly:

- AID;
- current keys and threshold;
- next-key digests and threshold;
- witnesses and `toad`;
- Cardano checkpoint `seq` and KERI `native_sn`.

Native registration sets the applied version and no origin. Advance may change
only the fields authenticated by its KERI rotation and retains version/origin.
Migration changes only version/origin and retains all KEL projection fields.

## `DAT-254-ARMED` — versioned in-flight challenge

- `checkpoint: DAT-254-CHECKPOINT`
- `hunter_pkh`
- `deadline`

Migration preserves all three fields and the ARMED role. FROZEN preserves the
versioned checkpoint and FROZEN role. Version-0 ARMED/FROZEN have no legacy
exit and therefore block the first cutover rather than being rewritten.

## `DAT-254-CHECKPOINT-TRANSITION`

Relationships:

- consumes exactly one source checkpoint identified by
  `(source_policy, derived_aid_asset_name, source_ref)`;
- burns exactly that token under source policy;
- mints exactly one token with the same asset name under target policy;
- creates exactly one target-role output containing `DAT-254-CHECKPOINT` (or
  `DAT-254-ARMED`) and the target token;
- carries the source role's exact protected value, subject only to the
  documented legacy refund/re-capitalization shape.

## `DAT-254-BOARD` — versioned board record

- `validator_version: DAT-254-VERSION`
- `migration_origin: Option<DAT-254-ORIGIN>`
- `record: BoardDatumForVersion`

Continuity fields across migration are witness key, endpoint content,
lifecycle owner key hash, and protected deposit. The target schema owns any
new signed sequence/context fields. For the #253 target, witness authorization
must bind endpoint content, owner, and monotonic sequence; generic migration
metadata cannot waive that check.

## `DAT-254-BOARD-TRANSITION`

Relationships:

- consumes one source marker named by witness key and burns it once;
- mints one same-name target marker and confines it to one successor;
- requires the source board owner's authorization and the target schema's
  witness authorization;
- preserves source deposit and continuity fields;
- records the exact predecessor origin.

The v0 bridge uses the frozen policy and existing `Retire`/`Burn`; later
versions use the permanent family migration actions.

## `DAT-254-REGISTRY` — validator-family registry

- `schema_version`
- `network`
- `earliest_scan_point: (slot, block_hash)`
- `checkpoint_versions: NonEmpty<CheckpointVersionEntry>`
- `board_versions: NonEmpty<BoardVersionEntry>`
- `cutover_status`

Each checkpoint entry contains version, policy, ACTIVE/ARMED/FROZEN addresses,
predecessor version/policy when any, script/reference identities, and source
commit. Each board entry contains the analogous version, policy/address,
predecessor, reference, and source identity.

Validation:

- versions are unique, ordered, and contiguous along each predecessor edge;
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
version, policy, role, outref, asset name, datum digest, and value digest.
Reconciliation pairs each source with exactly one settled successor and records
the migration transaction plus successor outref/digests.

Cutover completeness requires:

- no unpaired source or successor;
- no source paired twice;
- every source checkpoint ACTIVE for the v0 bridge;
- exactly the three expected board witness keys represented once each;
- consumer observation of both the source spend and successor creation.

## State transitions

- `Native(version N, origin=None) -> Migrate(version N+1, origin=source)`
- `Migrate/Native -> Advance(same version, same origin, KEL-authenticated state)`
- `ACTIVE(N) -> ARMED(N) -> ACTIVE/FROZEN(N)` retains version/origin.
- `ACTIVE|ARMED|FROZEN(N>=1) -> same role(N+1)` through migration.
- `ACTIVE(v0) -> ACTIVE(v1)` through the legacy checkpoint bridge only.
- `Board(v0) -> Board(v1)` through legacy Retire/Burn plus target entry.
- Any terminal burn has no migration successor and creates no identity datum.

## Data invariants

- `DATA-INV-254-01`: version/origin are transaction-verified metadata, never
  caller assertions.
- `DATA-INV-254-02`: migration preserves all KEL projection fields exactly.
- `DATA-INV-254-03`: source and target asset maps are exact singleton policy
  transitions with one confined successor.
- `DATA-INV-254-04`: role payload and protected value survive migration.
- `DATA-INV-254-05`: board continuity cannot bypass target authentication.
- `DATA-INV-254-06`: registry history and lineage edges remain sufficient for
  old/new bootstrap and rollback.
