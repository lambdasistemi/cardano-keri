# Modules model — #254 validator migration

Artifact ceiling: 9,000 bytes and 180 lines.

## `MOD-254-PROTOCOL` — shared migration contract

- **Status:** new shared owner.
- **Responsibility:** own applied predecessor-policy, target, role,
  authorization message, and structured migration verdict abstractions used by
  checkpoint and board families.
- **Owns abstractions:** `DAT-254-PREDECESSOR`, `DAT-254-TARGET`,
  `DAT-254-AUTHORIZATION`; `DAT-254-RELEASE` is registry-owned.
- **Upstream dependencies:** ledger output references, policy IDs, addresses,
  threshold/signature primitives, network discriminator.
- **Downstream consumers:** checkpoint migration, board migration, Haskell
  parity/generator, deployment packages, release registry.
- **Promotions:** none. Script hash identifies the release and transaction
  history owns lineage; neither is duplicated into shared datum state.
- **Forbidden dependencies:** no dependency on follower, query provider,
  governance key, deployment environment, or #253-specific endpoint content.

## `MOD-254-CHECKPOINT-STATE` — unchanged checkpoint role state

- **Status:** changed owner of checkpoint wire state.
- **Responsibility:** preserve the frozen V1 KEL projection and existing
  ACTIVE/ARMED/FROZEN role shapes without adding migration metadata.
- **Owns abstractions:** `DAT-254-CHECKPOINT`, `DAT-254-ARMED`.
- **Upstream dependencies:** frozen checkpoint V1 state.
- **Downstream consumers:** checkpoint spend/mint arm, observers, parity codec,
  consumer contract.
- **Promotions:** none; the KEL projection remains owned by the existing datum
  module and is referenced, not copied field-by-field into migration logic.
- **Forbidden dependencies:** migration metadata must not enter KEL state or
  alter registration/advance event semantics.

## `MOD-254-CHECKPOINT-FAMILY` — checkpoint migration enforcement

- **Status:** changed validator family.
- **Responsibility:** enforce normal migrate-out, applied-predecessor migrate-in,
  and the exact deployed-v0 ACTIVE bridge alongside existing lifecycle arms.
- **Owns abstractions:** checkpoint migration entry/exit redeemers and
  `FUN-254-CP-*` verdicts in `functions-model.md`.
- **Upstream dependencies:** `MOD-254-PROTOCOL`,
  `MOD-254-CHECKPOINT-STATE`, existing close/role/value/threshold rules.
- **Downstream consumers:** applied checkpoint program, deployment builder,
  M8 compiled proof.
- **Promotions:** heavy signature/parity checks may remain in an observer-sized
  component if applied-program limits require it; the responsibility and
  verdict stay here regardless of placement.
- **Forbidden dependencies:** no operator/governance authorization and no
  mutation of KEL fields during migration.

## `MOD-254-BOARD-STATE` — target board datum

- **Status:** changed board wire owner.
- **Responsibility:** use the target board schema directly while preserving
  witness/content/owner/deposit continuity; add no generic migration envelope.
- **Owns abstractions:** `DAT-254-BOARD` and the target-schema boundary used by
  #253.
- **Upstream dependencies:** `MOD-254-PROTOCOL`, existing board datum; #253
  supplies the target authentication schema before deployment.
- **Downstream consumers:** board family, board parity codec, board consumers.
- **Promotions:** none; endpoint authentication remains board-owned.
- **Forbidden dependencies:** generic migration code may not interpret or
  weaken #253's signed owner/sequence/content contract.

## `MOD-254-BOARD-FAMILY` — board migration enforcement

- **Status:** changed validator family.
- **Responsibility:** enforce normal board migrate-out/in and the exact frozen
  v0 Retire/Burn bridge, including one-for-one marker and deposit continuity.
- **Owns abstractions:** board migration entry/exit redeemers and
  `FUN-254-BOARD-*` verdicts.
- **Upstream dependencies:** `MOD-254-PROTOCOL`, `MOD-254-BOARD-STATE`, existing
  owner signer and marker rules.
- **Downstream consumers:** applied board program, deployment builder, M8
  compiled proof.
- **Promotions:** none.
- **Forbidden dependencies:** no checkpoint-controller substitution for board
  ownership and no acceptance of an unauthenticated target board schema.

## `MOD-254-PARITY` — generated cross-layer protocol mirror

- **Status:** changed shared proof owner.
- **Responsibility:** keep onchain and offchain encodings/verdicts identical for
  every retained authorization, checkpoint, and board migration
  case; generate vectors from the offchain source.
- **Owns abstractions:** vector cases and parity verdict mapping, not duplicate
  business rules.
- **Upstream dependencies:** both family contracts and existing generator
  conventions.
- **Downstream consumers:** onchain suites, offchain suites, deployment package
  decoding.
- **Promotions:** none.
- **Forbidden dependencies:** no hand-authored generated vectors or silent
  protocol-string/layout changes.

## `MOD-254-DEPLOYMENT` — packages, inventory, and dry-run reconciliation

- **Status:** changed deployment composition.
- **Responsibility:** construct controller-authorized migration packages,
  discover exact source rows, build family-matching transitions, and emit a
  reproducible inventory/reconciliation transcript for the desk-gated
  cutover.
- **Owns abstractions:** `DAT-254-PACKAGE`, `DAT-254-INVENTORY`,
  `DAT-254-RECONCILIATION`.
- **Upstream dependencies:** release registry, chain-query algebra, parity
  codec, transaction builder.
- **Downstream consumers:** future cutover operation and #166 documentation.
- **Promotions:** the release registry is promoted out of one manifest entry
  because deployment, follower, query, relayer, and M8 all consume it.
- **Forbidden dependencies:** no live submission before the desk release and
  no direct provider fallback outside the selected query interpreter.

## `MOD-254-REGISTRY` — supported validator-family release identity

- **Status:** new append-only deployment artifact.
- **Responsibility:** publish a minimal ordered label-to-hash map for
  checkpoint/board releases, accepted predecessor policies, role addresses,
  references, and earliest scan point while retaining historical releases.
- **Owns abstractions:** `DAT-254-REGISTRY`, `DAT-254-REGISTRY-ENTRY`.
- **Upstream dependencies:** applied script derivation and immutable release
  facts.
- **Downstream consumers:** `MOD-254-DEPLOYMENT`, #171 follower/query/relayer,
  #166, M8 target registry.
- **Promotions:** singular checkpoint and board locators become entries within
  the common registry; the old manifests remain immutable evidence.
- **Forbidden dependencies:** no consumer preference algorithm or chain state
  is stored in the release artifact.

## `MOD-254-CONSUMER-CONTRACT` — desk-negotiated seam

- **Status:** contract only; implementation belongs to #171.
- **Responsibility:** define multi-address observation, transaction-derived
  lineage validation, ambiguity, and family-neutral resolved-result semantics.
- **Owns abstractions:** only the draft contract in `plan.md`; no source files
  in #254.
- **Upstream dependencies:** `MOD-254-REGISTRY`, atomic migration transaction
  semantics.
- **Downstream consumers:** follower, local/hosted/third-party query tiers,
  relayer, CID consumer example, #166.
- **Promotions:** none until the milestone desk ratifies the seam owner.
- **Forbidden dependencies:** #254 must not edit #171 implementation or
  negotiate around the milestone desk.

## Dependency direction

- `PROTOCOL -> {CHECKPOINT-STATE, BOARD-STATE}` is forbidden; state families
  depend on the protocol, not the reverse.
- `{CHECKPOINT-FAMILY, BOARD-FAMILY} -> DEPLOYMENT` is forbidden; deployment
  consumes validators and cannot define their acceptance rules.
- `REGISTRY -> live query state` is forbidden; release identity is immutable.
- Consumer resolution may depend on registry/transaction history, but no
  validator depends on a consumer interpretation.
