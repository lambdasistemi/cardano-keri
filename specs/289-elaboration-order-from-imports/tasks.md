# tasks — #289

One slice, `S1`. All tasks land in a single bisect-safe commit; the gate cannot
pass on any proper prefix of them.

## S1 — derive elaboration order from declared imports

- [ ] **T289-1** `elaborate-ilean-root.sh` derives the compile sequence from
  each staged module's declared local `KeriBlaster.*` imports instead of
  lexical `sort`. Satisfies R1, S1.
- [ ] **T289-2** The derived order is deterministic and independent of argument
  order, by a stated tie-breaking rule. Satisfies R2, S3.
- [ ] **T289-3** An unresolved declared local import aborts before any
  elaboration, non-zero, with its own distinct `layer=` token. Satisfies R3,
  V1, S4.
- [ ] **T289-4** A dependency cycle aborts before any elaboration, non-zero,
  with its own distinct `layer=` token, naming the participants. Satisfies R4,
  V2, S4.
- [ ] **T289-5** `test-elaboration-order.sh` executes controls C1–C4 and fails
  if any control could not be applied. C1 constructs its own
  dependent-sorts-before-prerequisite case rather than relying on the current
  tracked names. Satisfies INV-289-CONTROL-CANNOT-PASS-VACUOUSLY.
- [ ] **T289-6** The `blaster` runner in `offchain/flake.nix` invokes the new
  harness, so the controls execute through the existing flake-owned entry
  point. Satisfies R7.
- [ ] **T289-7** The aggregate root still compiles last and no tracked Lean
  source changed. Satisfies R5, R6.
