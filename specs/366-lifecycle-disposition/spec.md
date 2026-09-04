# Retire the superseded Lifecycle machine

## Outcome

Remove the pre-D-036 `Lifecycle.lean` machine and its theorem support from the
compiled Lean surface. Keep the accepted checkpoint machine as the sole M1
lifecycle specification, and turn the legacy traceability table into an
explicit retirement ledger bound to the epic-owner ruling.

## Disposition decision

**DISP-366-DELETE — delete, do not bring to parity.** The old
`Lifecycle.lean`/`Goals.lean`/`Invariants.lean` cluster is self-contained behind
three root imports and predates the accepted D-036 to D-040 checkpoint design.
`Checkpoint.lean` already owns `stepFn`, `step_iff_stepFn`, replay
correspondence, the simulator driver, and its finite mutation campaign. Giving
the old machine those mechanisms would create a second executable lifecycle
with obsolete states and guarantees instead of resolving the ambiguity.

Authority: [epic ruling of 2026-09-04](https://github.com/lambdasistemi/cardano-keri/issues/366#issuecomment-5543757547).

## Requirements

- **R366-1 — one lifecycle machine.** Delete
  `lean/CardanoKeri/{Lifecycle,Goals,Invariants}.lean`; the compiled root imports
  the live Checkpoint/Registry surface and no retired module.
- **R366-2 — clean traceability.** `lean/traceability.csv` contains no
  `PENDING` sentinel. Every theorem of the deleted 21-row legacy table is
  recorded exactly once as `RETIRED` with the owner-ruling URL.
- **R366-3 — reference disposition.** Lean README, CI, and traceability-driver
  language describe the live machine and the retired table accurately. No
  simulator or on-chain behavior changes.
- **R366-4 — compiled absence.** A clean Lake build succeeds from the root
  import, while a fresh attempt to import `CardanoKeri.Lifecycle`,
  `CardanoKeri.Goals`, or `CardanoKeri.Invariants` fails as an unknown module.
- **R366-5 — proof trust.** The clean build reports no `sorry`; generated
  `#print axioms` checks over every theorem in the live Checkpoint, Registry,
  Cage, and Samaritan theorem modules contain no `sorryAx` or unapproved axiom.

## Invariants

- **INV-366-SOLE-SPEC (BLOCKING):** the compiled public Lean root exposes one
  M1 lifecycle specification, the accepted Checkpoint machine; a retired
  machine cannot remain importable from a clean build.
- **INV-366-RETIREMENT-LEDGER (ADVISORY):** the historical 21-theorem extent is
  complete, unique, explicitly `RETIRED`, and bound to the owner ruling; no
  `PENDING` survives.
- **INV-366-PROOF-TRUST (BLOCKING):** all live theorem modules compile from a
  clean `.lake` with no proof escape axiom; every discovered theorem is included
  in the axiom probe.
- **INV-366-SCOPE (ADVISORY):** changes are limited to the disposition files,
  its traceability/CI driver, documentation references, and this mandate; no
  simulator, on-chain, off-chain behavior, or audit-report artifact changes.

## Non-goals

- The whole-tree audit verdict moved to #368.
- Repairing any finding or changing accepted Checkpoint/Registry semantics.
- Simulator or on-chain edits beyond reference disposition.
- Merge.

## Acceptance

A fresh alternate-family commit auditor must pass the complete candidate and
the immutable gate. The ticket owner then verifies the exact final tree, pushes
the accepted SHA, waits for green CI, and marks the draft ready for review.

