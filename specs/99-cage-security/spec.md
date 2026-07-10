# Specification: Restore cage token and AID-ownership invariants

Issue: lambdasistemi/cardano-keri#99. Parent epic: #21.
Security prerequisite for #24, #25, #26, #44. Supersedes the security claims of
#23 where the current `mpfCage` validator does not meet its acceptance criteria.

## Problem

The current `mpfCage` validator (`onchain/validators/cage.ak`, combined
mint+spend, parameterized `mpfCage(_version: Int)`) is too permissive. Six
distinct attack surfaces let an attacker — or an oracle acting alone — break the
cage's core guarantees: one unique confined thread token per cage, no
attacker-selected migration ancestry, and an oracle that is *necessary but never
sufficient* to manufacture AID authority or mutate another AID's leaf.

All six were confirmed by code inspection (see `plan.md` §"Attack surfaces").
There is currently **no full-transaction test harness** in the main onchain tree
(`cage.tests.ak` only exercises the pure `verifyOwnerAuth` helper), so token
confinement and input/output coupling are entirely unproven.

## P1 user story

As a cage integrator, I submit Mint, Migrate, Modify, and End transactions and
observe that the validator preserves exactly one confined cage thread token and
rejects every oracle-only or attacker-only mutation of an AID-owned leaf — with
each rejection demonstrated by a full-transaction test that the current
implementation fails.

## User stories

- **US1 — Unique confined mint.** As an integrator, minting a cage produces
  exactly one asset under the cage policy, derived from a consumed output
  reference, and that exact token sits in the designated state output at the
  cage script; nothing else under the policy is minted.
- **US2 — Owner-authorized end.** As a cage owner, ending my cage burns exactly
  the matching thread token coupled to my owner-authorized `End` spend; no
  positive quantity under the cage policy can be minted under any redeemer.
- **US3 — Pinned migration.** As an integrator, migrating a cage burns exactly
  one genuine predecessor token under an explicitly pinned predecessor
  policy/version and mints exactly one confined successor; an attacker-created
  predecessor policy is rejected.
- **US4 — Confined modify.** As an integrator, modifying a cage requires the
  exact cage thread token in the continuing state output; preserving only the
  address or datum is insufficient.
- **US5 — Authenticated authority.** As a security reviewer, owner
  authorization is evaluated against an authenticated input/reference identity
  state; changing the output `identity_root` in the same transaction cannot
  introduce new authority.
- **US6 — Bound namespace.** As an AID owner, every mutated value key is
  cryptographically bound to the authenticated AID by carrying
  `blake2b_256(owner_aid)` as its first 32 bytes; possession of an unrelated
  registered AID, or a raw-`owner_aid` prefix collision, cannot authorize the
  key.

## Functional requirements

Each FR maps to an issue acceptance-criterion (AC1–AC8) and the attack
hypothesis it closes (H1–H6).

- **FR1 (AC2, H3-mint).** `Minting` permits exactly one asset under the cage
  policy, derives the asset name from the consumed output reference, requires
  that exact token in the checked state output at the cage script, and rejects
  any additional asset name or extra quantity under the cage policy.
- **FR2 (AC1, H1+H6).** `Burning` rejects every transaction with a positive
  quantity under the cage policy and accepts only the exact matching thread-token
  burn coupled to its owner-authorized `End` spend, proven as one exact
  state-token lifecycle transition; a burn without the matching owner-authorized
  `End`, and any mismatched or extra cage-policy mint entry, are rejected.
- **FR3 (AC3, H2).** `Migrating` accepts only an explicitly pinned predecessor
  policy/version, burns exactly one matching predecessor token, mints exactly
  one successor token confined in the state output, and rejects an
  attacker-created predecessor policy as well as any extra or non-exact
  predecessor/successor policy quantity or asset name.
- **FR4 (AC4, H3-modify).** `Modify` requires the exact cage thread token in the
  designated continuing state output; address or datum preservation alone is
  insufficient. This output-confinement guard is delivered in **Slice 5** (it
  blocks a no-burn `Modify` from moving the token out of the cage). It is
  **distinct from and additive to** the Slice 3 reverse guard — Slice 3 forbids a
  `Modify` from minting or burning its own thread token (required for H6
  Burn↔End exclusivity); Slice 5 forbids a `Modify` from moving it out. Slice 5
  must preserve the Slice 3 check, not replace or revert it.
- **FR5 (AC5, H4).** Owner authorization is evaluated against an authenticated
  input/reference identity root; changing the output `identity_root` cannot
  introduce new authority in the same transaction.
- **FR6 (AC6, H5).** Every mutated `requestKey` is cryptographically bound to
  the authenticated AID: the key MUST be at least 32 bytes and its first 32
  bytes MUST equal `blake2b_256(owner_aid)`. A key whose first 32 bytes are
  exactly that digest is the owner cell; a longer key is a namespaced child
  under that digest. A raw-`owner_aid` prefix (the AID bytes themselves, not
  their digest) and an unrelated authenticated AID are both rejected.
- **FR7 (AC7).** Attack-shaped full-transaction Aiken tests reproduce all six
  failures on the current implementation (RED) and pass after the fix (GREEN);
  happy-path Mint, Migrate, Modify, and End tests also pass.
- **FR8 (AC8, parity).** Any cross-layer wire-shape change carries a matching
  Haskell↔Aiken golden parity check; `just ci` and the ticket gate pass from a
  clean worktree.
- **FR9 (measurement).** The PR records Plutus V3 execution units for the
  hardened happy paths and the supported batch/output bound.
- **FR10 (status).** Public implementation-status text continues to label the
  system a prototype. #99 is described as one completed security gate among the
  work still required — never as the sole remaining reason for prototype status,
  and never as a claim of production readiness. Closing #99 does not lift the
  prototype label.

## Success criteria (issue acceptance, verbatim mapping)

- [ ] AC1 — `Burning` rejects every positive quantity; accepts only the exact
  thread-token burn coupled to owner-authorized `End`. (FR2)
- [ ] AC2 — `Minting` permits exactly one asset, derived from the consumed
  output reference, required in the checked state output. (FR1)
- [ ] AC3 — `Migrating` pins predecessor policy/version; 1 burn / 1 mint;
  rejects attacker predecessor. (FR3)
- [ ] AC4 — `Modify` requires the exact thread token in the continuing state
  output. (FR4)
- [ ] AC5 — Owner auth against authenticated input/reference root; output
  `identity_root` cannot introduce authority. (FR5)
- [ ] AC6 — Every mutated key bound to the authenticated AID namespace/owner
  cell; unrelated AID rejected. (FR6)
- [ ] AC7 — Attack-shaped full-tx tests RED→GREEN for all six; happy paths pass.
  (FR7)
- [ ] AC8 — Cross-layer wire changes have golden parity; `just ci` + gate green
  from a clean worktree. (FR8)
- [ ] AC9 — PR records execution units and the supported batch bound. (FR9)

## Out of scope (issue non-goals)

- KERI checkpoint registry, weighted threshold semantics, witness receipts, TEL,
  ACDC, WASM replay.
- Selecting attested vs cryptographic genesis (#91 owns this after #97).
- Mainnet/preprod deployment.
- Full legacy lifecycle policy beyond the pinned-predecessor and exact-token
  constraints required to close #99 (#26 owns the rest).
- Modifying parent #21 or sibling issue/PR metadata.

## Invariants preserved from siblings

- #97's exact 32-byte BLAKE3 digest semantics for any shared off-chain type.
- The prototype label (`docs/index.md` §Implementation status) persists; #99 is
  one completed gate and does not lift it.
