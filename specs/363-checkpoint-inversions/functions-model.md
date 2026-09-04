# Functions model — #363 Checkpoint constructor inversions

Artifact ceiling: 4,000 bytes and 100 lines.

Only new public proof/check signatures are modeled here. No implementation
bodies or algorithms are prescribed.

## FUN-363-INVERSION-FAMILY

For every constructor identity `Step.<ctor>`, export exactly one theorem named
`Step.<ctor>_iff`. Its parameters are the constructor's
non-proof parameters and its result type is **DAT-363-INVERSION-TYPE**.

Intake constructor identities are `register`, `rotateKeepPaid`,
`rotateKeepUnpaid`, `rotateDepositPaid`, `rotateDepositUnpaid`, `poison`,
`freeze`, `topUp`, `convict`, `convictParked`, `closePaid`, `closeUnpaid`, and
`reopen`. This observed list guides review; **DAT-363-CONSTRUCTOR-ROW** remains
the authoritative live denominator.

## FUN-363-COVERAGE

`checkpointStepInversionCoverage -> compiled command result`

Constraints:

- discovers `Step` constructors from the compiled environment;
- discovers only public inversions in the imported `CardanoKeri` surface;
- associates every inversion with exactly one constructor;
- validates exact canonical type, not spelling or theorem count alone;
- rejects empty, missing, duplicate, wrong-constructor, dropped/duplicated
  premise, changed-effect, and outside-surface cases;
- reports the complete **DAT-363-COVERAGE-RECEIPT** on success.

## FUN-363-AXIOMS

`printCheckpointInversionAxioms derivedInventory -> theorem-qualified output`

Runs after a clean build, covers exactly the derived inversion declarations,
and fails on `sorryAx`, `Classical.choice`, or any axiom other than `propext`
and `Quot.sound`.
