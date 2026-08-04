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

**Superseded (`NOTE-007`):** the fix landed here as `f664089`, then per
operator order was repackaged as a standalone PR against #235
(`fix/235-e2e-blueprint-fod-staleness`, PR #243), which also picked up an
ms8/blaster cross-consumer fix and a correction commit (`b0a52b4`) for two
bugs the main-based cherry-pick exposed (wrong size pin, unresolved
sandbox path). PR #243 **merged 2026-08-04**, closing #235. The tasks below
are satisfied by that merged PR, not by a commit on this branch — see
`spec.md`'s amendment. This branch now rebases onto the merged result: see
Slice A6.

- [x] T219-A4 Confirm whether `aiken build -t silent` is hermetic under the
      repo's pinned toolchain — yes; landed as fix shape (a) via #243.
- [x] T219-A4 Fix shape (a): converted `blueprint` to an ordinary
      input-addressed derivation — via #243, not this branch's own commit.
- [x] T219-A4 Enumerate all `blueprint` reference sites — done in #243's
      review (~22 sites; plus the missed ms8/blaster cross-consumer, fixed
      via `frozenM8Blueprint`).
- [x] T219-A4 Confirmed with evidence that the production deploy path never
      consumed this FOD by default divergence (it does consume the FOD via
      `ckeriRunner`'s baked default, which is exactly why the fix needed to
      make that FOD track source, not just document non-consumption — see
      `Q-006`/`A-006`).
- [x] T219-A4 Full gate green; landed via #243 (`514dc9f`, `b0a52b4`), not
      as a commit on this branch.
- [x] T219-A4 Confirmed `E2E (withDevnet)`-equivalent (`checks.deployment-tests`,
      `checks.blaster`) runs a freshly-rebuilt blueprint and goes green
      honestly, on #243. This branch's own `E2E (withDevnet)` run is
      Slice A6's job, now that main carries the fix.

## Slice A6 — rebase onto merged main, retire the superseded local A4 copy,
## rerun honest E2E

`f664089` (this branch's own copy of the A4 infra fix) and merged `main`'s
`514dc9f`/`b0a52b4` (via #243) both touch `offchain/flake.nix`,
`offchain/deployment-test/Cardano/KERI/Deployment/ManifestSpec.hs`, and
`offchain/e2e/CheckpointTxBuilder.hs` for overlapping reasons. Main's
version is the later, independently-accepted, CI-green one and wins.

- [x] T219-A6 Rebase `feat/219-permissionless-advance` onto post-merge
      `origin/main` (cherry-pick, dropping the superseded `f664089`;
      applied clean, git auto-merged the one real file overlap with zero
      conflict markers — no manual "ours"/"theirs" resolution was actually
      needed once `f664089` was correctly identified as dropped).
- [x] T219-A6 Neither `main`'s `15_647` pin nor this branch's original
      `14_775` pin was assumed correct for the rebased result. Re-measured
      `observer-advance`'s applied-program size fresh via a real PAIR
      slice (driver+navigator both independently rebuilt): confirmed
      `14,775` bytes — additive effect of `main`'s infra fix and this
      branch's own `advance.ak` deletions, not a reused number (commit
      `8fea43a3b432b50f7cc4d28bf37adbd1198e51a6`).
- [x] T219-A6 Full gate green on the rebased tree (ticket-owner's own
      independent `./gate.sh` rerun, exit 0).
- [x] T219-A6 (per operator order: verify locally, not via GitHub Actions)
      Real local `nix build .#checks.x86_64-linux.e2e` against an actual
      local devnet: 6 examples, 0 failures, including genuine `Advance`
      transactions validated on-chain with real `ExUnits` budgets. This is
      the original T219-A3 acceptance criterion, finally satisfiable now
      that the FOD staleness defect is fixed upstream of this branch —
      confirmed locally rather than by watching CI.
- [x] T219-A3 (resumed) Local full gate + local honest `checks.e2e` both
      green on the commit about to be pushed; PR description current;
      report `COMPLETE`.
