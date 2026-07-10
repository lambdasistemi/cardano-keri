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
- `onchain/validators/types.ak` (`Burning` gains a `TokenId`)
- `onchain/validators/cage.tests.ak`

Tasks:

- [X] T099-S3 RED (a): full-tx attack — positive mint accepted under `Burning`
  (otherwise-valid owner-authorized End; only defect is `+q`).
- [X] T099-S3 RED (b): full-tx attack — burn accepted with a mismatched /
  absent matching cage-state End spend (coupling defect, not merely absent
  signer).
- [X] T099-S3 RED (c): full-tx attack — burn accepted without the owner
  signature on the matching End spend.
- [X] T099-S3 RED (d): full-tx attack — mismatched / extra cage-policy mint
  entry accepted alongside the `-1`.
- [X] T099-S3 RED (e): full-tx attack — owner-signed `Burning(TokenId)` +
  `Modify([])` token-dropping burn accepted (burn via a non-`End` state spend;
  H6 reverse guard). Record observed counts RED→GREEN.
- [X] T099-S3 GREEN: `Burning` rejects every positive cage-policy quantity and
  accepts only exactly one cage-policy mint entry (the matching thread token at
  `-1`) coupled to the owner-authorized `End` spend; AND a `validModify`
  **reverse guard** — `Modify` may not mint or burn its own thread token — so an
  exact burn can coexist only with the owner-authorized `End` branch (one exact
  lifecycle transition; H6 exclusivity).
- [X] T099-S3 This reverse guard is **distinct from FR4**: it does NOT require
  the token in the continuing output. FR4/H3-modify output confinement (blocking
  a no-burn `Modify` from moving the token out) is a separate Slice-5 target,
  additive to this guard; S5 must preserve this S3 check, not revert it.
- [X] T099-S3 Keep the happy-path End + Modify accept tests green; keep Slice-2
  `validateMint` green.
- [X] T099-S3 `Burning(TokenId)` wire change is Aiken-only (no Haskell mirror);
  record the reasoning in `WIP.md`.
- [X] T099-S3 Run the focused command and `./gate.sh`.
- [X] T099-S3 Commit as `fix(onchain): couple cage burn to owner-authorized end`;
  commit body states the reverse guard (`validModify` refuses to mint/burn its
  own thread token) completing exact Burn↔End coupling.

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

- [X] T099-S4 RED (a): full-tx attack test — migration accepted from an
  attacker-created predecessor policy.
- [X] T099-S4 RED (b): full-tx attack test — extra or non-exact
  predecessor/successor policy quantity or asset name accepted.
- [X] T099-S4 GREEN: pin the predecessor policy/version (validator parameter or
  genuine-predecessor-spend at pinned version-1); exactly 1 predecessor burn /
  1 successor mint, rejecting extra entries under either policy; confine the
  successor token in the state output.
- [X] T099-S4 Keep the happy-path Migrate accept test green.
- [X] T099-S4 If the pinning mechanism cannot reject an attacker predecessor
  within AC3, BLOCK to the epic owner (do not weaken acceptance).
- [X] T099-S4 Run the focused command and `./gate.sh`.
- [X] T099-S4 Commit as `fix(onchain): pin cage migration predecessor and confine successor`.

Focused command:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check
```

## Slice 5 — Harden Modify confinement + authorization (FR4+FR5+FR6 / H3-modify+H4+H5)

FR4/H3-modify output confinement is a **genuine S5 RED→GREEN** target (distinct
from the S3 reverse guard). S5 must keep the S3 `validModify` no-mint/burn guard
intact (additive — not weaken/revert).

Owned files:

- `onchain/validators/cage.ak`
- `onchain/validators/types.ak` (only if a mirrored type's wire shape changes)
- `onchain/validators/cage.tests.ak`
- `offchain/lib/Cardano/KERI/AID/Cage/Types.hs` (only on a mirrored wire change)
- `offchain/test/Cardano/KERI/AID/Cage/TypesSpec.hs` (only on a mirrored wire change)
- `offchain/app/GenVectors.hs` (only if the auth message shape changes)

Tasks:

- [X] T099-S5 RED (a): a no-burn `Modify` moving the thread token OUT of the
  continuing state output accepted (FR4/H3-modify — the S3 reverse guard only
  blocks minting/burning the token, so this move-out is still open).
- [X] T099-S5 RED (b): output-`identity_root` self-authorization accepted (auth
  proven against the tx's own output root).
- [X] T099-S5 RED (c): an unrelated authenticated AID authorizes the key.
- [X] T099-S5 RED (d): a raw-`owner_aid` prefix (the AID bytes, not their
  `blake2b_256`) authorizes the key.
- [X] T099-S5 GREEN: require the exact thread token in the continuing state
  output (FR4); authenticate against the input/reference identity root (FR5);
  require `bytearray.length(requestKey) >= 32` and
  `bytearray.take(requestKey, 32) == blake2b_256(owner_aid)` (FR6); keep the S3
  no-mint/burn guard intact.
- [X] T099-S5 Keep the happy-path Modify accept test green.
- [X] T099-S5 If a mirrored type wire shape changes, update the Haskell mirror +
  `TypesSpec.hs` (+ regen vectors) in this same commit; else keep existing
  golden green and note "no cross-layer change" in `WIP.md`.
- [X] T099-S5 Run the focused commands and `./gate.sh`.
- [X] T099-S5 Commit as `fix(onchain): authenticate cage modify against input identity state`.

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

- [X] T099-S6 Add full-context `const` measurement fixtures invoking the
  hardened handlers on their accept path (Mint, Migrate, Modify at the supported
  batch size, End).
- [X] T099-S6 Run `aiken check --plain-numbers` and record memory/CPU per path.
- [X] T099-S6 Compare each to the mainnet per-tx budget (mem 14,000,000; CPU
  10,000,000,000); state the supported Modify batch/output bound.
- [X] T099-S6 Write `REPORT.md` with the fit verdict and the supported bound.
- [X] T099-S6 Run `./gate.sh`.
- [X] T099-S6 Commit as `docs(onchain): measure hardened cage execution units`.

Focused command:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check --plain-numbers
```

## Slice 7 — Prototype implementation-status text (FR10)

Owned files:

- `docs/index.md`

Tasks:

- [X] T099-S7 Keep the system labelled a prototype; describe #99 as one
  completed security gate among the work still required. Do NOT frame #99 as the
  sole remaining reason for prototype status, and do NOT claim production
  readiness; closing #99 does not lift the prototype label.
- [X] T099-S7 Run `./gate.sh`.
- [X] T099-S7 Commit as `docs: record cage security gate; keep prototype label`.

Focused command:

```sh
./gate.sh
```

## Slice 8 — Live-boundary measurement follow-up (FR9/AC9 boundary proof)

Owned files:

- `specs/99-cage-security/REPORT.md`
- `onchain/validators/cage_boundary.ak` (new — only if the UPLC-eval smoke is added)

Tasks:

- [X] T099-S8 Amend `REPORT.md`: distinguish "measured handler ceiling = 65"
  (source-level typed fixtures, empty single-leaf MPF proofs, ledger `Data`
  deserialization excluded) from a production-supported bound; remove guidance
  treating 65 as a safe on-chain cap.
- [X] T099-S8 Attempt an in-PR live-boundary smoke: `aiken build`/`aiken export`
  the Modify spend handler to UPLC with `Data`-encoded datum/redeemer/context
  applied, then `aiken uplc eval` (real mem/cpu incl. `Data` deserialization) at
  a **declared** representative/maximum MPF proof depth; record the
  boundary-inclusive number. Extend `gate.sh` with it only if it runs
  deterministically.
- [X] T099-S8 If the UPLC-eval smoke is infeasible in-scope, report the exact
  missing evaluator step (do not fake it).
- [X] T099-S8 Full node phase-2 boundary is out of local scope (no host
  `cardano-cli`/`node`/`uplc`; no #99 tx builder in repo). If neither smoke can
  be exercised safely in-scope, the orchestrator writes a parent Q-file naming
  the missing offchain #99 tx builder + `yaci-devkit` evaluation, a named
  operator artifact required before the PR leaves draft, and a conservative
  recommendation; AC9 is carried as that named follow-up, NOT claimed satisfied.
- [X] T099-S8 Do NOT alter the S6 commit `bc8d9b2` in place; fresh commit(s),
  pair-reviewed.
- [X] T099-S8 Run `./gate.sh`.
- [X] T099-S8 Commit as `docs(onchain): distinguish measured cage ceiling from production bound`.

Focused command:

```sh
cd onchain && nix shell nixpkgs#aiken --command aiken check
```

READ-ONLY precedent for Slices 9a/9b (never edit/clean/reset/commit — unrelated
user changes): `/code/cardano-mpfs-onchain` (`CageTxBuilder.hs`, `CageE2ESpec.hs`),
`/code/mpfs` (`trie/proof.ts`). All delivered edits live in the #99 worktree.
Do NOT use/restart the shared Yaci container, preprod, or mainnet.

## Slice 9a — toolchain + withDevnet cage builder + one real Phase-2 smoke (FR9/AC9)

Owned files:

- `offchain/cabal.project` (immutable `source-repository-package` pin of
  `cardano-node-clients` — owns the `devnet` sublibrary — reusing
  `cardano-tx-tools`'s exact rev + nix32 `--sha256:` comments; NOT
  `cardano-tx-tools` as a package dep unless a `Cardano.Tx.*` module is imported)
- `offchain/cardano-keri.cabal` (new e2e test/exe component + deps incl.
  `cardano-node-clients` `devnet` sublibrary)
- `offchain/e2e/**` (new Haskell — adapt read-only CageTxBuilder/CageE2ESpec to
  the hardened #99 wire)
- offchain flake wiring (`offchain/flake.nix`, `offchain/flake.lock`, + its `nix/`
  — E2E app + runCommand check modeled on `/code/cardano-tx-tools/nix/checks.nix`)
- `offchain/justfile`/`justfile`, `.github/workflows/ci.yml` (e2e job + upgraded
  dev-shell build job)

Tasks:

- [X] T099-S9a Pin the exact proven tx-tools pair: `cardano-node` **10.7.0** +
  `cardano-node-clients` **`ca86f11d27b34e37d3814e4d3c3d66e256400403`** in
  `offchain/flake.lock` and as an immutable `source-repository-package` (nix32
  `--sha256`) in `cabal.project`; the Cabal pin and the flake source for
  `E2E_GENESIS_DIR` MUST agree on that rev; no mutable-checkout dep.
- [X] T099-S9a RED→GREEN (NO RED-SKIP): first land a navigator-reviewed **failing**
  settled-`Modify` E2E spec (proves the boundary: submit + observe settlement),
  then make it green with the builder + wiring below.
- [X] T099-S9a Blueprint provenance (NOTE-016): the E2E must NOT consume the
  gitignored mutable `onchain/plutus.json`. Prefer a flake-owned `plutus-blueprint`
  derivation from tracked `../onchain` + `aiken.lock`, passed as an immutable path;
  fallback = committed fixture + a gate-invoked byte-for-byte freshness check vs a
  fresh `aiken build`.
- [X] T099-S9a Add the Haskell E2E component (`offchain/e2e/**`) adapting the
  read-only `CageTxBuilder.hs`/`CageE2ESpec.hs` to build a real `Modify` tx against
  the hardened #99 validator blueprint + current KERI cage wire; apply **BOTH**
  validator params (`version` + pinned `predecessorPolicy`), derive the mint/spend
  policy id from the applied bytes, and record the script hash in the artifact.
- [X] T099-S9a Submit ONE real `Modify` tx through `withDevnet` (real
  cardano-node) — NEVER Yaci/preprod/mainnet/unrelated containers — and observe it
  **settled** (not merely `evaluateTx = Right`); record the **tx id + per-redeemer
  execution units** (single smoke).
- [X] T099-S9a Flake wiring (model `cardano-tx-tools/nix/checks.nix`): one
  strict-PATH app exposed as `apps.<sys>.e2e` + `checks.<sys>.e2e` (runCommand
  invokes it via `getExe`); `runtimeInputs` = `cardano-node` + the E2E exe + std
  utils; `E2E_GENESIS_DIR` from the pinned `cardano-node-clients` source. E2E
  check/app may be Linux-only; keep other checks on all systems.
- [X] T099-S9a Add an E2E job to `.github/workflows/ci.yml` that INVOKES the E2E
  check (`nix flake check` / `nix run .#e2e`) — driver-owned. (The `gate.sh`
  extension is a SEPARATE orchestrator commit — task T099-S9a-GATE below — not
  part of this pair commit.)
- [X] T099-S9a Upgrade the dev-shell gate: replace the stale tool/format-only
  `just devshell-offchain` + CI dev-shell job with the proven
  `nix develop --quiet -c cabal build all --enable-tests -O0` (SAME command in
  `just` + CI); remove the stale "cabal build can't run" comment. Expose the
  `devnet` sublibrary via haskell.nix shell `additional` if the shell DB lacks it.
- [X] T099-S9a Keep PR #100 draft, `gate.sh` installed. Q-file the orchestrator on
  any ambiguous pin/`additional`-wiring/#99-wire adaptation.
- [X] T099-S9a Focused proof + `./gate.sh`; commit
  `test(e2e): add withDevnet #99 cage phase-2 smoke and dev-shell build gate`.

### Slice 9a-GATE — orchestrator-owned gate extension (after S9a acceptance)

- [X] T099-S9a-GATE After S9a is navigator-verified and accepted, the ticket
  owner extends `gate.sh` in its own mechanical commit
  `chore: extend gate.sh with #99 withDevnet e2e smoke` to invoke the repo-owned
  E2E app/check + the upgraded dev-shell build; run it immediately; keep it
  installed through S9b and final verification. (Separate from the pair's S9a
  code commit for truthful ownership/history; `ci.yml` is pair-owned, not part of
  this exception.)

Focused command:

```sh
cd offchain && nix flake check --no-eval-cache   # runs the e2e runCommand check
cd offchain && nix develop --quiet -c cabal build all --enable-tests -O0
```

## Slice 9b — non-zero-depth proof, batch sweep, artifact + report (FR9/AC9)

Owned files:

- `offchain/e2e/**` (proof generation + batch sweep; new modules ok)
- `offchain/cardano-keri.cabal` (mechanical `other-modules` registration of new
  `offchain/e2e/**` modules; A-001)
- `offchain/flake.nix` + `.github/workflows/ci.yml` (flake-owned `apps.e2e-sweep` +
  lightweight `checks.sweep-consistency` + dedicated CI job; A-002 — `gate.sh`
  untouched, heavy sweep kept out of the routine gate)
- `specs/99-cage-security/REPORT.md`

Tasks:

- [X] T099-S9b RED→GREEN: first land a navigator-reviewed **failing**
  non-zero-depth proof case, then make it green. The subsequent numerical batch
  sweep itself may use an explicitly logged measurement RED-SKIP.
- [X] T099-S9b Generate representative **non-zero-depth** MPF inclusion proofs
  (mpfs `trie/proof.ts` is a read-only precedent for fixtures/oracle).
- [X] T099-S9b Sweep `Modify` batch sizes at a **declared** proof depth + state
  shape through `withDevnet` until the pass/fail boundary is observed; record node
  Phase-2 results + ex-units as a repo-owned reproducible artifact (produced/
  verified by the flake check).
- [X] T099-S9b Failing boundary points (NOTE-016) preserve and report the ACTUAL
  Phase-2 evaluation/rejection diagnostic; do NOT retain placeholder ExUnits on
  `Left` (the read-only precedent does that — do not copy it).
- [X] T099-S9b Update `REPORT.md` with the **qualified** production bound (at the
  declared depth/state) + Phase-2 ex-units; no extrapolation as a universal cap.
- [X] T099-S9b Keep PR #100 draft. Rerun `./gate.sh` + `just ci`.
- [X] T099-S9b Commit
  `test(e2e): sweep #99 modify phase-2 batch bound at declared proof depth`.

Focused command:

```sh
cd offchain && nix flake check --no-eval-cache   # e2e sweep check
```

## Slice 9c — dev-shell cabal-build CI gate resolves CHaP offline (finalization CI fix, Q-003)

Discovered at finalization: the S9a `nix develop --quiet -c cabal build all
--enable-tests -O0` CI **"Dev shell"** job fails from a fresh CHaP-empty runner —
cabal tries to fetch the CHaP index (`chap.intersectmbo.org`) and dies with
`DnsHostNotFound` / `user error (https not supported)`. It passes locally only via
a cached CHaP index (a local/CI divergence). All other CI jobs (incl. E2E
withDevnet + batch sweep) pass. **Keep the gate; make it resolve offline.**

Owned files:

- `offchain/cabal.project` (repositories / `active-repositories` / index-state)
- `offchain/flake.nix` + its `nix/` (dev-shell cabal index / offline provisioning)
- `offchain/justfile` / `justfile` (`devshell-offchain` recipe, if the command changes)
- `.github/workflows/ci.yml` (Dev shell job pre-warm / env, if needed)

Tasks:

- [X] T099-S9c RED (reproduce FIRST): with an ISOLATED empty cabal cache
  (`CABAL_DIR`/`HOME`/`XDG_*` → a fresh temp dir, no CHaP index) run
  `nix develop --quiet -c cabal build all --enable-tests -O0` and observe the SAME
  CHaP-fetch failure the CI runner hits (`DnsHostNotFound` / `https not supported`).
  Navigator confirms it authentically reproduces the CI failure (not a stub).
- [X] T099-S9c GREEN: make the dev-shell cabal build resolve **offline** (no CHaP
  network fetch) — e.g. `active-repositories: :none` for the dev-shell build, a
  nix-provided cabal index / package DB, or a pre-warm step from a nix source.
  **KEEP** the gate (do not delete or weaken it — it must still prove a working
  dev-shell `cabal build`). Prove GREEN locally with the isolated empty cache.
- [X] T099-S9c Keep the SAME command in `just devshell-offchain` and the CI Dev
  shell job (or update both identically). Do NOT touch `gate.sh` (orchestrator).
- [X] T099-S9c Run `./gate.sh` + the isolated-cache focused proof; commit
  `build(offchain): resolve dev-shell cabal build offline for CHaP-empty CI`.

Focused command:

```sh
CABAL_DIR=$(mktemp -d) nix develop --quiet -c cabal build all --enable-tests -O0
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
