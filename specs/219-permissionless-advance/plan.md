# Plan: permissionless advance — authenticate rotation from the KEL (#219)

**Target branch**: `feat/219-permissionless-advance`
**Required base**: `origin/main` (c9c1f96 at branch cut)
**Spec**: `specs/219-permissionless-advance/spec.md`
**Status**: ratified (Q-001 answered by `A-001`, 2026-08-03)

## Summary

Move `advance.ak`'s controller-signature verification (V5) from the
reconstructed `AdvanceMessage` CBOR preimage onto `event_bytes` directly —
the same move `0f6a88c` made for registration's R7 — then delete the
`AdvanceMessage`/`advance_domain`/`reconstruct_advance_message` layer once
nothing verifies against it, restating the two checks that were genuinely
load-bearing (eq2 AID continuity, eq5 sequence monotonicity) as direct
`spent`-vs-`new` structural checks. No fixture regeneration is needed:
`offchain/test/keri-fixtures/fixtures/advance.json` already carries
`rot_sigs` with `signing_target: "event_raw"` (genuine KERI controller
signatures over the raw `rot` bytes), exactly analogous to registration's
pre-existing `event_sigs`.

## Constitution check

- Existing protocol strings/domains are deleted only with their obsolete
  feature, never repurposed (mirrors #114's rule).
- Keripy remains the byte/signature oracle; Haskell remains the generated
  vector source; Aiken consumes verbatim output — this is why the Haskell
  parity mirror is phase-1 scope (`A-001`): the rule cannot be honored from
  `onchain/` alone.
- RED precedes GREEN; the anti-replay property is proven falsifiable
  (RED against a deliberately weakened variant) before it is proven to hold.
- The pair owns only the named #219 files; #115/#114 behavior, #181's
  tx-building surface, and #220's surfaces remain untouched.
- No deployment or redeploy action; a proposed cutover plan is filed as a Q
  on acceptance.

## Owned surface (ratified by `A-001`)

```text
onchain/lib/cardano_keri/checkpoint/advance.ak
onchain/lib/cardano_keri/checkpoint/advance_tests.ak
onchain/lib/cardano_keri/checkpoint/advance_vectors.ak
onchain/lib/cardano_keri/checkpoint/message.ak
onchain/lib/cardano_keri/checkpoint/message_tests.ak
onchain/lib/cardano_keri/checkpoint/vectors.ak            (if AdvanceMessage goldens live here)
onchain/validators/checkpoint.ak                            (only if SpentCheckpoint/wiring shape changes)
onchain/validators/checkpoint_tests.ak
offchain/lib/Cardano/KERI/AID/Checkpoint/Advance.hs
offchain/lib/Cardano/KERI/AID/Checkpoint/Message.hs
offchain/test/Cardano/KERI/AID/Checkpoint/AdvanceSpec.hs
offchain/test/Cardano/KERI/AID/Checkpoint/AdvanceFixturesSpec.hs
offchain/test/Cardano/KERI/AID/Checkpoint/MessageSpec.hs
offchain/app/GenAdvanceVectors.hs
offchain/app/GenCheckpointVectors.hs         (driver Q-001 -> A-001: delete AdvanceMessage goldens here)
offchain/e2e/CheckpointTxBuilder.hs          (driver Q-001 -> A-001: signedRotateEvidence signs event_bytes directly)
offchain/deployment-test/Cardano/KERI/Deployment/AdvanceSpec.hs   (driver Q-003 -> A-003: one stale assertion, see "Emergent CLI permissionlessness" below)
offchain/flake.nix   (Q-005 -> A-005: the `blueprint` derivation block ONLY -- desk-granted, see "E2E blueprint fixed-output-derivation staleness" in spec.md; no other flake surface)
specs/219-permissionless-advance/{spec.md,plan.md,tasks.md}
docs/user/rotate-preprod-identity.md
```

No new fixture capture: `advance.json`'s existing `rot_sigs`/`event_raw`
suffices — mirrors `0f6a88c`'s real file list for registration exactly,
swapping Registration→Advance. Goldens under `onchain/` are produced BY the
generator, never hand-edited.

**Cross-fence leftover (driver `Q-001` -> ticket-owner `A-001`):**
`AdvanceMessage`/`advance_domain`/`reconstruct_advance_message` stay
**defined** (not deleted) in the two `offchain/lib/.../{Advance,Message}.hs`
files above, unused by the validation path, Haddock-noted as retained only
for `offchain/deployment/Cardano/KERI/Deployment/Advance.hs`'s still-forbidden
import — a tracked phase-2/#181 fast-follow deletes them. See spec.md
"Cross-fence leftover" for the full reasoning.

**Forbidden (unconditional):**

```text
offchain/deployment/**
scripts/kli-sign-advance.py
the ckeri advance CLI surface (--controller-signatures, --signing-package)
cabal/project files, CI workflows, any offchain/ path not listed above
onchain/lib/cardano_keri/checkpoint/registration*.ak
onchain/lib/cardano_keri/checkpoint/close*.ak
onchain/lib/cardano_keri/checkpoint/enforcement*.ak
onchain/lib/cardano_keri/checkpoint/freeze_bond*.ak
```

A file outside the enumerated owned list that turns out necessary is a new
Q, not a judgment call (`A-001`).

## Anti-replay design decision

Recorded normatively in `spec.md` ("Anti-replay analysis"). Summary for the
pair: eq3 (`Eq3OutRefMismatch`)/eq4 (`Eq4PriorMismatch`)/eq1
(`Eq1NetworkPolicyMismatch`) are tautological in the wired `advance_predicate`
today (their message-side value is always copied 1:1 from `spent`/`own_ref`
by `reconstruct_advance_message`, never from evidence) and are deleted with
the message layer, not preserved as unreachable code. eq2 (AID continuity)
and eq5 (sequence monotonicity: `new.seq == spent.seq + 1`,
`new.native_sn > spent.native_sn`) are genuinely load-bearing and are
restated as direct checks between the real `spent`/`new` datums. Anti-replay
after this change rests entirely on: (a) eq5's structural sequencing between
the actual spent and created datums (never routed through signed evidence),
and (b) AE1-AE10's binding of the KERI event's own fields — especially AE3's
`s`-to-`native_sn` pin — to that same created datum. Do not invent a third
mechanism (e.g., a fresh nonce, a re-added txid-shaped field) — if the pair
finds this insufficient, STOP and file a Q rather than improvise. `A-001`
confirms this reading and attaches a condition: the weakened-variant RED
property (slice A1 step 2) must target **eq5 itself**, not the AE3/message
layer being deleted — proving the mechanism that actually carries
anti-replay today can fail, not a mechanism that never carried it. If the
eq3/eq4 tautology analysis turns out wrong under test (they DO bind
evidence somewhere the pair finds), STOP and file a fresh Q — that changes
the risk profile of the whole change.

## Slices

### Slice A1 (PAIR) — event-own advance authorization + anti-replay proof

1. **RED (permissionless-holds).** Add a property test constructing
   `AdvanceEvidence` from only `event_bytes` + the fixture's existing
   `rot_sigs` (`signing_target: "event_raw"`) — no Cardano-domain preimage
   signing step, no `spent_txid`/`spent_index` knowledge threaded in. Prove
   it fails on the current validator (it demands a signature over the
   `AdvanceMessage` preimage the stranger cannot produce).
2. **RED (anti-replay falsifiability).** Add a property test asserting an
   already-applied `rot` event cannot re-advance a checkpoint that has moved
   past its `native_sn`. Prove this property is *falsifiable* against a
   deliberately weakened **eq5** (e.g. `new.seq >= spent.seq` instead of
   `== spent.seq + 1`, or dropping the strict `native_sn` increase) and
   observe it fails to catch the replay — i.e., the test is capable of
   failing, and it is the real mechanism (eq5), not AE3 or the message
   layer being deleted, that the weakening targets (`A-001` condition 3).
3. **GREEN.** In `advance.ak`: change V5 (`verified_indices`/`ctrl_sigs`
   verification) to check against `e.event_bytes` instead of
   `cbor.serialise(reconstruct_advance_message(...))`. Delete
   `reconstruct_advance_message`, `AdvanceMessage`, `advance_domain` from
   `message.ak` once nothing references them. Restate `advance_equalities`'s
   surviving checks (AID continuity, sequence monotonicity) as direct
   `spent`-vs-`new` checks with no message indirection; remove
   `Eq1NetworkPolicyMismatch`, `Eq3OutRefMismatch`, `Eq4PriorMismatch` and
   their now-meaningless message fields. Re-run both RED tests: the
   permissionless-holds test now passes; the anti-replay test now correctly
   rejects the replay via the real (non-weakened) AE3/eq5 binding.
4. Full `aiken check` green: registration/close/enforcement/freeze-bond/
   lifecycle-model suites unaffected; every existing advance positive/
   negative vector that exercised eq2/eq5/AE1-AE10 still passes with
   byte-identical verdicts. Vectors that only ever exercised now-deleted
   dead constructors (eq1/eq3/eq4 message-field mismatches) are removed,
   not weakened-in-place.
5. Amend `offchain/lib/Cardano/KERI/AID/Checkpoint/{Advance,Message}.hs` in
   lockstep (mirrors `0f6a88c`'s `Registration.hs`/`Message.hs` edit), point
   `GenAdvanceVectors.hs` at the fixture's existing `rot_sigs`/`event_raw`
   entries instead of computing a fresh preimage signature, and regenerate
   `advance_vectors.ak` byte-identically-except-for-the-intended-changes.
   Run the Haskell/Aiken drift check — it must never be red on a landed
   commit (`A-001` condition 1).
6. Land the Haskell+generator+goldens+Aiken change as ONE commit (or an
   ordered series where every commit keeps `just ci` green — if that's
   impossible, one commit): exactly
   `refactor(219): authenticate advance events from the KEL` with exactly
   `Tasks: T219-A1`.

### Slice A2 (PAIR, may fold into A1's commit if the pair finds no natural
split) — docs

1. Rewrite `docs/user/rotate-preprod-identity.md` "Why signing has two
   steps": state there is one signing step (the native KERI `rot`
   signatures), explain the stranger-submittable consequence, and mark the
   `ckeri advance --controller-signatures`/`kli-sign-advance.py` procedural
   section provisional pending #219 phase 2 (after #181).
2. Commit as part of A1, or as a separate
   `docs(219): describe permissionless advance signing` with
   `Tasks: T219-A2`, at the pair's discretion — the brief requires docs in
   the same diff as the behavior change, not necessarily the same commit
   object, but they must land on this branch before `COMPLETE`.

## Verification commands

- `cd onchain && aiken check` (fast inner loop, every iteration)
- `./gate.sh` (v3) before every commit — `just check-onchain` +
  `just ci-onchain ci-blake3` + `ci-offchain`'s recipes named individually,
  minus `check-advance-vectors`/`check-checkpoint-vectors` (git-diff-vs-HEAD
  can never pass pre-commit for a slice that legitimately changes those
  generated files — navigator `GATE-CHALLENGE-002`/`A-GATE-CHALLENGE-002`),
  replaced pre-commit with a regenerate-twice idempotency proof. A timeout
  is `GATE-INCOMPLETE`, not a verdict — the nix store was GC'd mid-slice
  (2026-08-03T~11:05Z); rerun warm, record cold/warm elapsed per the
  machine-owner ask.
- At ticket-level final acceptance (post-commit, ticket owner only, from a
  fresh clean detached worktree at the accepted commit): the real
  `just check-advance-vectors`/`just check-checkpoint-vectors`
  (git-diff-vs-HEAD form, unmodified) run directly — meaningful again once
  the commit exists — alongside full `just ci`.

## Reporting

Ticket owner reports `SLICE-START`/`SLICE-ACCEPTED` per
[[ticket-orchestrator]] tags; PR body refreshed after each push per
[[resolve-ticket]] §"PR communication".
