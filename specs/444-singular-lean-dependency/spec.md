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

## Re-cut provenance

This campaign supersedes #442, which stopped before implementation after its
single gate repair remained incomplete. The terminal report is SHA256
`0ea6ea1f545a5068d926311e0db638a599a8380bfe86be426172fec434ddf32e`.
Historical slice spend remains charged: 16/60 cheap and 0/4 expensive, leaving
44 cheap and 4 expensive executions for this successor.

## Requirements

- **R-444-PIN:** Lake declares Singular as a Git dependency pinned to
  `v0.6.1`; a disposable fresh resolution equals the tracked manifest, and the
  checkout actually consumed by the build is clean at its peeled commit.
- **R-444-IMPORT:** Building the default `CardanoKeri` library elaborates the
  released `Singular` root library.
- **R-444-STEP:** A committed executable check calls the released
  `Singular.step` and verifies its exact observable result for a fully
  specified input.
- **R-444-CONTROL:** Replacing that input with a different well-typed action
  while keeping the expected result makes the executable check fail for a
  result mismatch; wrong-proposition and nonempty-axiom controls also fail;
  restoring the intended check passes.
- **R-444-BUILDS:** Both `CardanoKeri` and `CardanoKeriStatements` build.
- **R-444-DOCS:** `lean/README.md` has one ordered dependency block whose
  unique fields name the release pin, executable binding, and non-migration
  boundary.

## Invariants

- **INV-444-PROVENANCE — ADVISORY:** The declared release and Lake's resolved
  Git revision identify the same Singular release commit. Failure means the
  declared and compiled dependencies can drift. Success is an executable
  comparison of declared and resolved identities.
- **INV-444-EXECUTION — ADVISORY:** The default Cardano KERI build elaborates
  a call to the dependency's actual `Singular.step`. Failure means the import
  or real transition is absent. Success requires the committed check plus an
  independent consumer probe, each observed failing under its own deliberate
  fault.
- **INV-444-COMPATIBILITY — ADVISORY:** The dependency does not break either
  Cardano KERI Lean library. Failure is an elaboration/build error in either
  target; success is a fresh build of both targets.

## Rejection behavior

- A branch or local-path dependency is rejected.
- A tag whose resolved revision is not the released `v0.6.1` commit is
  rejected.
- Source-text presence without executing `Singular.step` is rejected.
- A negative control that fails through setup or import failure is rejected.
- A gate that ignores failed or truncated Git discovery is rejected.
- A gate runner checked only once before several invocations is rejected.

## Non-goals

- Migrating Cardano KERI registry semantics or proofs onto Singular.
- Choosing the Cardano KERI leaf-to-Singular representation.
- Changing Singular's model, release, or naming lifecycle.
- Repairing Cardano KERI's release planner or stale release PR.

## Ceiling

This file is limited to 4 KiB and 100 lines.
