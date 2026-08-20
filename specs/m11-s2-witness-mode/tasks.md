# Tasks — S2 witness-mode

One slice, `s2w-witness-mode`, `OWNER` topology. Checked by the ticket owner after the fresh
auditor passes the exact candidate; the commit owner never checks its own tasks.

## Slice `s2w-witness-mode`

- [x] **T001** Executable RED for the whole contract: both named examples
      (`witness-mode/REFERENCE`, `witness-mode/INLINE`) failing at the assertion level, not at
      compile. A compile failure is setup, not RED. (S2W-R1, R2, R3)
- [x] **T002** `M12TxB` with one plan type and one construction entry point taking an explicit
      carriage mode; production selection defined in terms of it. (S2W-R1, S2W-I1)
- [x] **T003** INLINE rendering preserved as a live path over the same plan, executed in the
      focused suite, serialized size measured. (S2W-R2, S2W-I2)
- [x] **T004** Pinned protocol quantities read and cited with provenance — package, tarball
      digest, snapshot/genesis. (S2W-R4, S2W-I3)
- [x] **T005** Reference-script fee derived from the pinned parameters and probed at
      25,599 / 25,600 / 25,601 / 25,617 / 26,448, with the stride boundary revealed. (S2W-R5, S2W-I4)
- [x] **T006** Per-program **signed** creation-transaction envelope measured, with its own limit,
      that limit's provenance, and a verdict derived from the measurement — reported separately
      from the aggregate. (S2W-R6, S2W-I5)
- [x] **T007** Aggregate reported as the sum of the measured program sizes, never asserted
      independently. (S2W-I6)
- [x] **T008** Manifest carries the archived-RED Surface-B object and its evidence hash; no
      `surface_b_sha` shape, argument or validator survives from the seed. (S2W-R7, S2W-I7)
- [x] **T009** S0 binary-content digest control carried and agreeing with the candidate's own
      `scripts/s0/measure-family.sh`; that script is not edited. (S2W-R8, S2W-I8)
- [x] **T010** Residuals `A3-F1` (ADVISORY) and `F1-ERROR-CLASSIFICATION` (OPEN, verbatim
      classification) labeled in both manifest and report. (S2W-R9, S2W-I9)
- [x] **T011** `WITNESS-MODE-REPORT.md` states the determination, the two limits, the fee-tier
      result, the caveats and the residuals — with no inherited number. (S2W-R10)
- [x] **T012** Shared `testPParams` gains the pinned fee parameter against its then-current shape;
      every existing reader stays green.
- [x] **T013** Final re-integration of then-current `origin/main`, every byte-dependent baseline
      regenerated, complete gate, fresh audit and CI rerun on the resulting SHA. (S2W-I10)
