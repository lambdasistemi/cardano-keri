# Feature specification — #262 ChainQuery-only write acquisition

Artifact ceiling: 6,000 bytes and 150 lines.

## Outcome

Every transaction build-phase chain read used by the eight write verbs is a
`ChainQuery` operation interpreted by the local interpreter. No write builder
can reach a raw local-store `Transaction` acquisition route.

## Requirements

- **RQ-262-01 — exact output operation:** the algebra can resolve one live
  output by validated transaction id and output index, returning the existing
  provider-neutral full output representation and failing closed on absence,
  duplication, malformed identity, or reconstruction data.
- **RQ-262-02 — spendable board catalog:** the algebra can return every
  authenticated board entry paired with the full provider-neutral output from
  the same row; any missing, duplicated, malformed, or mismatched pair fails
  the whole operation.
- **RQ-262-03 — eager validation:** concrete output and board locators are
  rejected before an interpreter effect runs.
- **RQ-262-04 — compositional programs:** each build phase composes all of its
  reads in one `ChainQuery` program and invokes the local runner once. No read
  occurs while a transaction builder runs.
- **RQ-262-05 — sole acquisition route:** raw build-phase local readers and the
  raw snapshot runner cease to be exported to write composition after all
  callers migrate. Concrete local transaction functions remain private
  interpreter implementation details.
- **RQ-262-06 — interpreter completeness:** the abstract interpreter factory,
  dispatcher, local interpreter, Koios interpreter, and all test interpreters
  account explicitly for both new operation families; no default or fallback
  dispatch is introduced.
- **RQ-262-07 — disposition:** every shipped occurrence of
  `INV-240-LOCALTIER` states that algebra-only local routing is now met by
  #262. The executing #240 deferral detector is changed in the same behavior
  commit into a closure detector and is proved able to reject restored
  deferral text.
- **RQ-262-08 — retained behavior:** #240's no-provider boundary, atomic
  snapshot evidence, fail-closed decoding, reference/funding behavior, and
  frozen acquisition parity remain green.

## Invariants

- **INV-262-SOLE-ROUTE (BLOCKING):** every write build-phase read resolves
  through the local `ChainQueryInterpreter`, which is the sole acquisition
  authority. A mutation restoring a direct local `Transaction` acquisition in
  any write verb must make the permanent check RED.
- **INV-262-NO-REGRESSION (BLOCKING):** no provider becomes reachable; every
  verb retains one atomic local snapshot per build phase; decoded acquisition
  values remain equal to #240's frozen behavior. A seeded escaped read or
  acquisition perturbation must make the proof RED.
- **INV-262-DISPOSITION (BLOCKING):** no shipped source says
  `INV-240-LOCALTIER` is open or deferred to #262 after the migration. A
  restored deferral must make the executing disposition check RED.

## Rejection behavior

- Invalid locators produce `InvalidLocator` without provider/store effects.
- Missing or malformed exact outputs and board/output pairs fail closed with a
  named `ChainQueryError`; no partial catalog and no provider fallback exists.
- A local scope missing the identity required by an operation fails before a
  scan.

## Non-goals

- Settlement polling remains a separate temporal capability and is not added
  to the snapshot algebra.
- No Blockfrost or other provider implementation is added.
- #263's deployed endpoint-board blueprint mismatch is unchanged.
- #240's already-established parity and snapshot framework is extended, not
  replaced.
