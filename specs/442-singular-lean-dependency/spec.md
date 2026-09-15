# Specification: Singular Lean dependency binding

## Paramount user story

As a Cardano KERI Lean maintainer, I build `CardanoKeri` against the pinned
Singular release and observe an executable binding to the real
`Singular.step` transition.

## Frozen authorities

- Cardano KERI base: `0e638fadc987f0cd98f839edd3e3ecd5a09a1b91`.
- Singular release: `v0.6.1`; annotated tag object
  `06eccccf849f7a465e8b2252fbfdc82b380d8fa2`; peeled commit
  `41861a66b72a840042f2e633ce33a607e817d6c6`.
- Accepted Cardano KERI Lean remains the behavioral authority for Cardano KERI.
  This ticket binds a dependency and does not migrate registry behavior.

## Requirements

- **R-442-PIN:** Lake declares Singular as a Git dependency pinned to
  `v0.6.1`, and the resolved manifest identifies its peeled commit.
- **R-442-IMPORT:** Building the default `CardanoKeri` library elaborates the
  released `Singular` root library.
- **R-442-STEP:** A committed executable check calls the released
  `Singular.step` and verifies its exact observable result for a fully
  specified input.
- **R-442-CONTROL:** Replacing that input with a different well-typed action
  while keeping the expected result makes the executable check fail for a
  result mismatch; restoring the intended action makes it pass.
- **R-442-BUILDS:** Both `CardanoKeri` and `CardanoKeriStatements` build.
- **R-442-DOCS:** `lean/README.md` names the release pin and the executable
  binding check without claiming model migration.

## Invariants

- **INV-442-PROVENANCE — ADVISORY:** The declared release and Lake's resolved
  Git revision identify the same Singular release commit. Failure means the
  declared and compiled dependencies can drift. Success is an executable
  comparison of declared and resolved identities.
- **INV-442-EXECUTION — ADVISORY:** The default Cardano KERI build elaborates
  a call to the dependency's actual `Singular.step`. Failure means the import
  or real transition is absent. Success requires the committed check plus an
  independent consumer probe, each observed failing under its own deliberate
  fault.
- **INV-442-COMPATIBILITY — ADVISORY:** The dependency does not break either
  Cardano KERI Lean library. Failure is an elaboration/build error in either
  target; success is a fresh build of both targets.

## Rejection behavior

- A branch or local-path dependency is rejected.
- A tag whose resolved revision is not the released `v0.6.1` commit is
  rejected.
- Source-text presence without executing `Singular.step` is rejected.
- A negative control that fails through setup or import failure is rejected.

## Non-goals

- Migrating Cardano KERI registry semantics or proofs onto Singular.
- Choosing the Cardano KERI leaf-to-Singular representation.
- Changing Singular's model, release, or naming lifecycle.
- Repairing Cardano KERI's release planner or stale release PR.

## Ceiling

This file is limited to 4 KiB and 100 lines.
