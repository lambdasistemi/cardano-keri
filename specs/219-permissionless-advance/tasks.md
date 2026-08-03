# Tasks: permissionless advance — authenticate rotation from the KEL (#219)

Anti-replay design decision recorded in `spec.md`/`plan.md` before dispatch,
per the brief's "STOP and file a Q rather than invent a third mechanism"
contract. Q-001 (offchain parity-mirror scope) is answered (`A-001`,
Option 1 granted): the Haskell-mirror tasks below are unconditional owned
scope.

## Dependency barrier

- [x] T219-A0 Read issue #219 in full; study `0f6a88c` (registration's
      equivalent fix) as the direct precedent.
- [x] T219-A0 Create the branch from current `origin/main`
      (`c9c1f96`); bootstrap the worktree.
- [x] T219-A0 Record the anti-replay analysis in `spec.md`: eq1/eq3/eq4 are
      tautological dead code in the wired `advance_predicate`; eq2/eq5 and
      AE1-AE10 are the real, surviving anti-replay/identity-continuity
      mechanism.
- [x] T219-A0 Resolve Q-001 (offchain parity-mirror scope) before finalizing
      the slice gate's writable-path fence — `A-001`, Option 1 granted.
- [x] T219-A0 Bootstrap and validate `gate.sh`, open the draft PR, pass the
      cross-artifact planning audit before pair dispatch.

## Slice A1 — event-own advance authorization + anti-replay proof

- [x] T219-A1 RED: a property test proves a stranger holding only
      `event_bytes` + the fixture's existing `rot_sigs`
      (`signing_target: "event_raw"`) cannot currently produce accepted
      `AdvanceEvidence` (current validator demands the `AdvanceMessage`-
      preimage signature).
- [x] T219-A1 RED: an anti-replay property test is proven *falsifiable* —
      run against a deliberately weakened **eq5** (the real mechanism, not
      AE3 or the deleted message layer — `A-001` condition 3) and observe it
      fails to catch a replay of an already-applied `rot` event onto a later
      checkpoint state.
- [x] T219-A1 GREEN: `advance.ak` V5 verifies `ctrl_sigs` against
      `event_bytes`; `AdvanceMessage`/`advance_domain`/
      `reconstruct_advance_message` deleted from `message.ak`; eq2 (AID
      continuity) and eq5 (sequence monotonicity) restated as direct
      `spent`-vs-`new` checks; `Eq1NetworkPolicyMismatch`/
      `Eq3OutRefMismatch`/`Eq4PriorMismatch` removed with their dead fields.
- [x] T219-A1 Both RED tests now pass for the stated reason (permissionless-
      holds accepted; anti-replay rejects the real replay via the
      non-weakened binding).
- [x] T219-A1 Full `aiken check` green: registration/close/enforcement/
      freeze-bond/lifecycle-model suites unaffected; surviving advance
      vectors byte/verdict-identical; dead-constructor-only vectors removed.
- [x] T219-A1 Amend `offchain/lib/Cardano/KERI/AID/Checkpoint/{Advance,
      Message}.hs` and `offchain/app/GenAdvanceVectors.hs` to consume the
      fixture's existing `rot_sigs`/`event_raw` entries; regenerate
      `advance_vectors.ak`; Haskell/Aiken drift check green.
- [x] T219-A1 (driver Q-001 -> A-001) Delete `AdvanceMessage` construction in
      `offchain/app/GenCheckpointVectors.hs` and
      `offchain/e2e/CheckpointTxBuilder.hs`; retain the bare
      `AdvanceMessage`/`advance_domain`/`reconstruct_advance_message`
      Haskell definitions, Haddock-noted, solely for
      `offchain/deployment/Cardano/KERI/Deployment/Advance.hs`'s forbidden
      import — do not touch that file.
- [x] T219-A1 Full gate green; land the Haskell+generator+goldens+Aiken
      change as ONE commit (or an ordered series that keeps `just ci` green
      throughout) exactly `refactor(219): authenticate advance events from
      the KEL` with exactly `Tasks: T219-A1`.

## Slice A2 — operator docs

- [x] T219-A2 Rewrite `docs/user/rotate-preprod-identity.md` "Why signing
      has two steps" to describe one signing step (the native KERI `rot`
      signatures) and the stranger-submittable consequence; mark the
      `--controller-signatures`/`kli-sign-advance.py` CLI section
      provisional pending #219 phase 2 (after #181).
- [x] T219-A2 Full gate green; commit (folded into A1 or standalone, pair's
      discretion) with `Tasks: T219-A2` if standalone. (Landed folded into
      the `7e88d87` T219-A1 commit — pair's discretion, per this task's own
      wording.)

## Report barrier

- [x] T219-A3 File a Q proposing the preprod V1 redeploy/cutover plan
      (manifest, live-consumer re-pin sequencing) without executing it.
      (`Q-004-preprod-redeploy-cutover-plan.md`, filed to the desk.)
- [x] T219-A3 Full repo gate green on the accepted commit (ticket-owner-run
      `just ci`, fresh detached worktree at `7e88d87`, zero errors
      end-to-end — real drift checks included).
- [ ] T219-A3 Real GitHub Actions CI green on the pushed PR, **including an
      honest `E2E (withDevnet)`** (see Slice A4 — retracted once found to be
      testing a stale cached blueprint, not this branch's source); PR
      description current; labels + assignee (`paolino`) set; report
      `COMPLETE` only after.

## Slice A4 — E2E blueprint fixed-output-derivation fix (desk `A-005`)

`E2E (withDevnet)` failed on the pushed PR. Traced to a pre-existing,
project-wide defect: `offchain/flake.nix`'s `blueprint` derivation is a Nix
fixed-output derivation pinned since `8edfa8b` and never updated —
content-addressed caching has likely been silently substituting a frozen,
ancient compiled script for every PR since, decoupling `E2E (withDevnet)`
from actual `onchain/` source changes. #219 is the first change whose
Haskell-side behavior diverges enough from that frozen script to cause a
hard on-chain rejection instead of silently continuing to agree by
accident. Full evidence: `Q-005-e2e-blueprint-fod-stale-cache.md` /
`A-005-e2e-blueprint-fod-stale-cache.md`. Infra issue:
lambdasistemi/cardano-keri#235.

Fence: the blueprint derivation block in `offchain/flake.nix` only (desk
`A-005`, extending `A-001`'s scope). No other flake surface.

- [ ] T219-A4 Confirm whether `aiken build -t silent` is hermetic under the
      repo's pinned toolchain (no network access needed once package
      dependencies are resolved) — determines fix shape (a) vs (b) below.
- [ ] T219-A4 Fix shape (a), preferred: convert `blueprint` to an ordinary
      input-addressed derivation if hermetic — staleness becomes
      structurally impossible.
- [ ] T219-A4 Fix shape (b), fallback (document why (a) doesn't hold): keep
      the FOD but add a CI drift check that rebuilds from source with the
      pinned `aiken` and reds on mismatch, mirroring
      `check-checkpoint-vectors`/`check-advance-vectors`.
- [ ] T219-A4 Enumerate all ~22 `blueprint` reference sites in
      `offchain/flake.nix` and state which build paths consume it.
- [ ] T219-A4 Confirm with evidence (not inference) that the production
      deploy path (`ckeri deploy`/`manifest verify`,
      `deploy/preprod/m1-manifest.json`) never consumed this FOD.
- [ ] T219-A4 Full gate green; land as its own bisect-safe commit(s),
      separate from the T219-A1 commit, with its own `Tasks: T219-A4`
      trailer.
- [ ] T219-A4 Push; confirm `E2E (withDevnet)` runs a freshly-rebuilt
      blueprint (verify via CI log: `aiken build`/`Generating project's
      blueprint` now appears) and goes green honestly.
