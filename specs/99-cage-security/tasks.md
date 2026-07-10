# Tasks: Restore cage token and AID-ownership invariants

Issue task trailer for behavior-changing commits: `Tasks: T099`

## Bootstrap

- [X] T099-B1 Add `./gate.sh` as the first branch commit.
- [X] T099-B2 Open draft PR #100 for `fix/99-cage-security`, labeled `fix`,
  assigned to `paolino`.
- [X] T099-B3 Commit and push this spec, plan, and task breakdown before
  dispatching implementation slices.

## Slice 1 — Full-transaction test harness

Owned files:

- `onchain/validators/cage_context.ak` (new — full-context constructors)
- `onchain/validators/cage.tests.ak`

Tasks:

- [X] T099-S1 Add reusable `Transaction`/`Input`/`Output`/`OutputReference`/
  `Value`/datum constructors built on `transaction.placeholder`.
- [X] T099-S1 Add full-tx happy-path fixtures + accept tests for Mint, Migrate,
  Modify, End that pass on current code (regression baseline).
- [X] T099-S1 No `mpfCage` behavior change in this slice.
- [X] T099-S1 Run the focused command and `./gate.sh`.
- [X] T099-S1 Commit as `test(onchain): add full-transaction cage test harness`.

Focused command:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check
```

## Slice 2 — Harden Minting confinement (FR1 / H3-mint)

Owned files:

- `onchain/validators/cage.ak`
- `onchain/validators/cage.tests.ak`

Tasks:

- [X] T099-S2 RED (a): full-tx attack test — mint accepted with the thread
  token absent from / outside the designated state output.
- [X] T099-S2 RED (b): full-tx attack test — mint accepted with an additional
  asset name (or extra quantity) under the cage policy.
- [X] T099-S2 GREEN: require exactly one cage-policy asset at quantity 1
  (derived from the consumed output reference) present in the state output at
  the cage script; reject any extra asset name/quantity under the policy.
- [X] T099-S2 Keep the happy-path Mint accept test green.
- [X] T099-S2 Run the focused command and `./gate.sh`.
- [X] T099-S2 Commit as `fix(onchain): confine minted cage token to the state output`.

Focused command:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check
```

## Slice 3 — Harden Burn/End lifecycle (FR2 / H1+H6)

Owned files:

- `onchain/validators/cage.ak`
- `onchain/validators/types.ak` (only if `Burning` gains a `TokenId`)
- `onchain/validators/cage.tests.ak`

Tasks:

- [ ] T099-S3 RED (a): full-tx attack test — positive mint accepted under
  `Burning`.
- [ ] T099-S3 RED (b): full-tx attack test — burn/`End` accepted without the
  matching owner-authorized `End` spend.
- [ ] T099-S3 RED (c): full-tx attack test — a mismatched or extra cage-policy
  mint entry accepted alongside the burn.
- [ ] T099-S3 GREEN: `Burning` rejects every positive cage-policy quantity and
  accepts only exactly one cage-policy mint entry (the matching thread token at
  `-1`) coupled to the owner-authorized `End` spend (one exact lifecycle
  transition).
- [ ] T099-S3 Keep the happy-path End accept test green.
- [ ] T099-S3 If `Burning` wire shape changes, it is Aiken-only (no Haskell
  mirror today); record the reasoning in `WIP.md`.
- [ ] T099-S3 Run the focused command and `./gate.sh`.
- [ ] T099-S3 Commit as `fix(onchain): couple cage burn to owner-authorized end`.

Focused command:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check
```

## Slice 4 — Harden Migrating pin + confinement (FR3 / H2+H3-migration)

Owned files:

- `onchain/validators/cage.ak`
- `onchain/validators/types.ak`
- `onchain/validators/cage.tests.ak`

Tasks:

- [ ] T099-S4 RED (a): full-tx attack test — migration accepted from an
  attacker-created predecessor policy.
- [ ] T099-S4 RED (b): full-tx attack test — extra or non-exact
  predecessor/successor policy quantity or asset name accepted.
- [ ] T099-S4 GREEN: pin the predecessor policy/version (validator parameter or
  genuine-predecessor-spend at pinned version-1); exactly 1 predecessor burn /
  1 successor mint, rejecting extra entries under either policy; confine the
  successor token in the state output.
- [ ] T099-S4 Keep the happy-path Migrate accept test green.
- [ ] T099-S4 If the pinning mechanism cannot reject an attacker predecessor
  within AC3, BLOCK to the epic owner (do not weaken acceptance).
- [ ] T099-S4 Run the focused command and `./gate.sh`.
- [ ] T099-S4 Commit as `fix(onchain): pin cage migration predecessor and confine successor`.

Focused command:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check
```

## Slice 5 — Harden Modify confinement + authorization (FR4+FR5+FR6 / H3-modify+H4+H5)

Owned files:

- `onchain/validators/cage.ak`
- `onchain/validators/types.ak` (only if a mirrored type's wire shape changes)
- `onchain/validators/cage.tests.ak`
- `offchain/lib/Cardano/KERI/AID/Cage/Types.hs` (only on a mirrored wire change)
- `offchain/test/Cardano/KERI/AID/Cage/TypesSpec.hs` (only on a mirrored wire change)
- `offchain/app/GenVectors.hs` (only if the auth message shape changes)

Tasks:

- [ ] T099-S5 RED (a): token-dropping Modify accepted (thread token absent from
  the continuing state output).
- [ ] T099-S5 RED (b): output-`identity_root` self-authorization accepted (auth
  proven against the tx's own output root).
- [ ] T099-S5 RED (c): an unrelated authenticated AID authorizes the key.
- [ ] T099-S5 RED (d): a raw-`owner_aid` prefix (the AID bytes, not their
  `blake2b_256`) authorizes the key.
- [ ] T099-S5 GREEN: require the exact thread token in the continuing state
  output; authenticate against the input/reference identity root; require
  `bytearray.length(requestKey) >= 32` and
  `bytearray.take(requestKey, 32) == blake2b_256(owner_aid)`.
- [ ] T099-S5 Keep the happy-path Modify accept test green.
- [ ] T099-S5 If a mirrored type wire shape changes, update the Haskell mirror +
  `TypesSpec.hs` (+ regen vectors) in this same commit; else keep existing
  golden green and note "no cross-layer change" in `WIP.md`.
- [ ] T099-S5 Run the focused commands and `./gate.sh`.
- [ ] T099-S5 Commit as `fix(onchain): authenticate cage modify against input identity state`.

Focused commands:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check
just unit "Cage"   # only if the offchain parity files changed
```

## Slice 6 — Execution-unit measurements + supported bound (FR9)

Owned files:

- `onchain/validators/cage_measurements.ak` (new)
- `specs/99-cage-security/REPORT.md` (new)

Tasks:

- [ ] T099-S6 Add full-context `const` measurement fixtures invoking the
  hardened handlers on their accept path (Mint, Migrate, Modify at the supported
  batch size, End).
- [ ] T099-S6 Run `aiken check --plain-numbers` and record memory/CPU per path.
- [ ] T099-S6 Compare each to the mainnet per-tx budget (mem 14,000,000; CPU
  10,000,000,000); state the supported Modify batch/output bound.
- [ ] T099-S6 Write `REPORT.md` with the fit verdict and the supported bound.
- [ ] T099-S6 Run `./gate.sh`.
- [ ] T099-S6 Commit as `docs(onchain): measure hardened cage execution units`.

Focused command:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check --plain-numbers
```

## Slice 7 — Prototype implementation-status text (FR10)

Owned files:

- `docs/index.md`

Tasks:

- [ ] T099-S7 Keep the system labelled a prototype; describe #99 as one
  completed security gate among the work still required. Do NOT frame #99 as the
  sole remaining reason for prototype status, and do NOT claim production
  readiness; closing #99 does not lift the prototype label.
- [ ] T099-S7 Run `./gate.sh`.
- [ ] T099-S7 Commit as `docs: record cage security gate; keep prototype label`.

Focused command:

```sh
./gate.sh
```

## Finalization

- [ ] T099-F1 Update PR #100 body with delivered behavior, execution units,
  supported bound, attack paths proven RED→GREEN, and verification evidence.
- [ ] T099-F2 Rerun `./gate.sh` and `just ci` at HEAD and record results.
- [ ] T099-F3 Run the finalization audit for PR #100 and
  `specs/99-cage-security/tasks.md`.
- [ ] T099-F4 Drop `gate.sh` in `chore: drop gate.sh (ready for review)`.
- [ ] T099-F5 Mark the PR ready only after local gate and CI are green; leave
  merge to the epic owner.
