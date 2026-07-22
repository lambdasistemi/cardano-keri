# Tasks: reopen #114 — permissionless bonded registration

A-014 ratified this packet; #116 and the audit fixes are merged on main.
Behavior slices are RED -> GREEN; measurement, E2E, and documentation slices
are separately gated commits. Every slice gate reports applied program bytes,
delta from 19,565, and margin to the 16,133-byte deployable budget.

## Dependency barrier

- [x] T114-R0 Create the #114 branch only from merged reopened #116; verify
      Register, Advance, and Close are staging-closed and final `B`/`W_freeze` arity
      is present; held #117's `W_close` remains separate and unapplied.
- [x] T114-R0 Record **NO DEPLOY** until #115 enables Advance and #117 enables
      Close/resolution; retain the NON-DEPLOYABLE banner in PR, measurements,
      and E2E output and the #115 size hard stop.
- [x] T114-R0 Bootstrap and validate `gate.sh`, open the draft PR, and pass the
      cross-artifact planning audit before pair dispatch.

## Slice R1 — witnessed inception oracle

- [x] T114-R1 RED: fixture tests require indexed witnessed-inception receipts
      over exact raw bytes and reject every non-`event_raw` signature target.
- [x] T114-R1 GREEN: extend the deterministic keripy generator and committed
      registration/manifest JSON; retain exact bytes, offsets, event
      signatures, and drift stability.
- [x] T114-R1 Full gate green; commit exactly
      `test(114): export witnessed inception receipts` with exactly
      `Tasks: T114-R1`.
- [x] T114-R1 Report applied program bytes, delta from 19,565, and 16,133-byte
      budget margin; do not make a deployment claim.

## Slice R2 — event-own registration predicate

- [x] T114-R2 RED: replace preimage positives with KERI `event_sigs` and
      receipt-quorum cases; pin old-message-only, bad/duplicate index,
      wrong-byte/key/witness, below-threshold/toad, and toad-zero negatives.
- [x] T114-R2 GREEN: change Haskell/Aiken RegistrationEvidence and predicates
      to distinct controller/receipt verification over `event_bytes`, keeping
      all E1-E9/schema/threshold rules; regenerate vectors.
- [x] T114-R2 Delete inception-only InceptionMessage production/preimage/
      private-signing surface from Message modules/tests without touching
      AdvanceMessage or repurposing the old domain.
- [x] T114-R2 Prove live Register remains staging-closed, full gate green, and
      commit exactly `refactor(114): authenticate inception events from the KEL`
      with exactly `Tasks: T114-R2`.
- [x] T114-R2 Report applied program bytes and both standing deltas; audit the
      21 traceability rows without flipping a sentinel lacking executable tests.

## Slice R3 — live bonded Register

- [x] T114-R3 RED: full contexts require permissionless event-own auth and at
      least `minADA+D_reg+B` plus one AID token for fresh/duplicate/
      post-conviction registration; pin floor/one-below, conservative-surplus,
      donation, and all existing mint/proof/output/offset canaries.
- [x] T114-R3 GREEN: reopen only Register, use applied #116 parameters, reject
      short reserve, extra AID-policy assets, and controller-chosen parameter
      values while accepting checkpoint-custodied surplus lovelace/assets;
      retain unrelated input tolerance and repeatable registration.
- [x] T114-R3 Preserve generic deployment parameters with independent
      5,000,000-lovelace floors/one-below negatives; fixtures use
      `D_reg=1,000,000,000` and `B=5,000,000`.
- [x] T114-R3 Vector #114's normative anti-griefing family: Register consumes
      no existing checkpoint, duplicates/post-conviction registrations create
      independent state outputs, and hostile submissions can project only the
      real signed+witnessed inception event, never a same-UTxO busy lock.
- [x] T114-R3 Audit all 21 traceability rows and prove the required CI job
      remains green. Flip a PENDING row only if this slice independently adds
      both mapped executable tests; do not import Convict/Reap behavior to
      manufacture a mapping change.
- [x] T114-R3 Prove Advance and Close remain fail closed, no registry/absence
      proof/mint-once/batcher/sequencer exists, and full gate green.
- [x] T114-R3 Commit exactly
      `feat(114): enable permissionless bonded registration` with exactly
      `Tasks: T114-R3`.
- [x] T114-R3 Report applied program bytes and both standing deltas.

## Slice R4 — registration measurements

- [x] T114-R4 Measure full 2-key unwitnessed, witnessed 2-of-2/2-of-3, and
      GLEIF-shaped 7-key Register handlers with proof burn, signatures,
      receipts, reserve-floor/conservative-surplus values, and final arity;
      write `specs/114-permissionless-registration/MEASUREMENTS.md`.
- [x] T114-R4 HARD STOP if any memory or CPU row has less than 25.00%
      headroom; no fixture or handler weakening.
- [x] T114-R4 Audit Haskell/Aiken parity, generated drift, net fresh-signing
      deletion, no forbidden coordinator, and full gate.
- [x] T114-R4 Record exact applied program bytes, delta from 19,565, and margin
      to 16,133 with a prominent NON-DEPLOYABLE verdict; restate the #115 hard
      stop and A-015 remediation order.
- [x] T114-R4 Commit exactly
      `test(114): measure permissionless registration` with exactly
      `Tasks: T114-R4`.

## Slice R5a — current-production devnet state

- [ ] T114-R5a RED: start the real devnet, query/assert the 251-entry V3
      pre-transition lineage, reproduce the production hash-proof settlement
      failure under stale parameters, and record the pinned node version.
- [ ] T114-R5a Prove whether the pinned node can enact PV 11. A node bump is
      authorized only if this probe fails; if changed, record old/new versions,
      compatibility verdict, and the exact lock delta.
- [ ] T114-R5a Commit the full 2026-07-22 mainnet parameter snapshot in an E2E
      fixture with provenance naming date, network, node/socket lineage, PV
      11.0, and source SHA-256; record the same-day preprod digest as a
      cross-check.
- [ ] T114-R5a GREEN: submit/enact the real parameter/hard-fork transition,
      poll it, then query/assert PV 11.0 and exact equality with all 350 V3
      entries before settling a real production hash-proof mint. No genesis
      cost-model patch, synthetic evaluator, pending case, or waiver.
- [ ] T114-R5a Preserve the single genesis delta and drift proof exactly as
      `maxTxSize 16384 -> 32768`; do not alter genesis exunits. A live witness
      may use 16.5M/10B, while the measurement gate stays at the stricter
      internal 14M/10B ceiling; correct the false E2E “mainnet 14M” comment.
- [ ] T114-R5a Run the focused real-node test, both withDevnet jobs, and full
      gate; report program bytes and both standing deltas; commit exactly
      `test(114): initialize production cost model on devnet` with exactly
      `Tasks: T114-R5a`.

## Slice R5 — staged checkpoint devnet

- [ ] T114-R5 Restore the byte-verified suspended R5 patch, rebase its narrow
      harness overlap onto R5a, and prove the resulting diff contains only the
      approved R5 lifecycle surface.
- [ ] T114-R5 RED: replace #116's Register staging rejection/pending scenarios
      with the exact #114 live-boundary expectation matrix.
- [ ] T114-R5 GREEN: on a real devnet settle hash-proof mint + permissionless
      Register with `D_reg+B` escrow after the queried PV11/350 initialization,
      then settle Arm against that fresh production-lineage checkpoint.
- [ ] T114-R5 Exercise Claim according to the actual #116 dispatch at this
      head—positive if live, explicit Phase-2 rejection if intentionally
      closed—and leave no Claim scenario hidden as pending.
- [ ] T114-R5 Prove Advance and Close still reach the production validator and
      reject; retain the single-field 32-KiB genesis override, drift proof, and
      loud NON-DEPLOYABLE output banner.
- [ ] T114-R5 Report current bytes and both standing deltas, run both withDevnet
      jobs and the full gate, and commit exactly
      `test(114): settle permissionless registration on devnet` with exactly
      `Tasks: T114-R5`.

## Slice R6 — registration documentation

- [ ] T114-R6 Driver/navigator update only “Inception transaction” in
      `docs/architecture/veridian-bridge.md`, the registration/duplicate
      fragment in `docs/design/trust-model.md`, the named M1 blog registration
      fragments, and the named M1 deck registration fragments.
- [ ] T114-R6 Remove fresh Cardano-signing, registered-once, and anti-squat
      claims; explain public event-own authentication, re-registration,
      protected `D_reg+B`, conservative surplus, and third-party donation.
- [ ] T114-R6 Correct every #114-owned claim that 14M/10B is the live mainnet
      maximum: it is the stricter internal measurement ceiling; the
      2026-07-22 live mainnet/preprod maximum is 16.5M/10B.
- [ ] T114-R6 Make the theorem central: M1 blog single-UTxO argument + state
      machine + per-move table with Register row; trust-model normative
      advance-totality/bounded-interference; deck one-liner “anyone can project
      the public truth; no one can lie about it or lock you out of it.”
- [ ] T114-R6 Name CLOSING `0x03`, distinct `W_close`, required one-tx ordinary
      Advance-void, and no cryptographic express-close in every held-#117
      mention; never conflate `W_close` with `W_freeze`.
- [ ] T114-R6 Preserve the burn axiom: conviction is recorded in the transaction,
      burns the checkpoint, and permits fresh registration; add no tombstone or
      #117 reap behavior.
- [ ] T114-R6 Leave #115 normal-Advance and #116 freeze fragments untouched;
      run `mkdocs build --strict`, lychee, and the full gate.
- [ ] T114-R6 Report final bytes and both standing deltas, then commit exactly
      `docs(114): explain permissionless bonded registration` with exactly
      `Tasks: T114-R6`, then park at Q-017. Do not deploy, dispatch #117, mark ready,
      or merge without instruction.
