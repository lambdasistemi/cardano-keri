# S0 per-script size fail-fast

Artifact ceiling: 9,000 bytes / 180 lines.

## Outcome

Measure honest, separately compiled skeletons for every member of the M1.2
record+cursor family before deep behavior work begins. The result is an
architectural go/redesign verdict, not a deployability claim.

## Family surface

The measured family has exactly seven members:

1. `append`
2. `cursor`
3. `lineage`
4. `maintenance_escrow`
5. `staging_proof_token`
6. `consumer_predicates`
7. `reference_cursor_consumer`

`consumer_predicates` is a dedicated measurement validator that compiles the
consumer predicate library into its own program. It is not evidence that an
Aiken library has an independent ledger script identity.

Staging is the Tx-A premint (inherited 1024-byte Blake3 SAID + pair token).
Append and cursor are Tx-B: they total-parse, bind decoded SAID/AID to that
digest, and burn the matching token. Script size below 16,384 still does
not prove either transaction fits.

## Requirements

- **S0-R01 Separate programs.** The blueprint contains exactly one uniquely
  titled program for each family member, and the harness measures each
  `compiledCode` independently.
- **S0-R02 Honest skeletons.** Each skeleton contains the role's cost-bearing
  parse, proof, or transition surface named in `modules-model.md`. A validator
  that merely decodes a redeemer/datum and returns a constant is hollow.
- **S0-R03 Scope boundary.** Skeletons exercise representative operations but
  do not claim S2-complete lifecycle, authorization, or adversarial behavior.
- **S0-R04 Metrics.** Every row reports integer compiled bytes, percentage of
  16,133 bytes, headroom to 16,133 bytes, percentage of 16,384 bytes, and
  headroom to 16,384 bytes.
- **S0-R05 Redesign trigger.** Any skeleton above 80% of the tighter 16,133-byte
  reference-program ceiling is named `REDESIGN`; no deep work is authorized for
  it. The integer boundary is 12,906 bytes pass / 12,907 bytes redesign.
- **S0-R06 Caveat.** Every published row and every bare verdict states that a
  script below 16,384 bytes does not prove its transaction fits. The same
  caveat remains present for an oversized script.
- **S0-R07 Toolchain identity.** Measurement uses
  `/nix/store/zk3s76mjwcb5fz099d6dq02c684bg8wn-aiken-1.1.23/bin/aiken` and
  records its freshly recomputed SHA-256. The expected digest is
  `c248f991a51176fe9e7b1c08b47939a1c55be3c1aebe3ca544d546640360e689`.
- **S0-R08 TTY execution.** Aiken build/check commands run under
  `script -qec '<command>' /dev/null` so diagnostics and exit status are real.
- **S0-R09 Anti-stub control.** A permanent control checks the declared
  cost-bearing obligation set before accepting measurements. The same control
  is run against a deliberately hollow seven-member fixture and must exit
  non-zero for an anti-stub reason.
- **S0-R10 Mechanical evidence.** Raw command output and real exit codes are
  captured in immutable runtime evidence. The report points at evidence hashes.
- **S0-R11 Build serialization.** Every Aiken realizing/build command owns the
  atomic `/tmp/ms-keri-11/BUILD-TOKEN`, records the immediately preceding
  `/nix/store` available-byte reading, refuses to start below 53.10 GiB, stops
  at or below 50.00 GiB, and releases the token on exit.
- **S0-R12 Verdict latency.** Each valid per-member result is journaled as a
  bare verdict immediately; reporting does not wait for the narrative or the
  remaining members.

## Invariants

- **S0-I01 FAMILY-7:** missing, duplicate, or unexpected family titles fail.
- **S0-I02 SEPARATE:** every row is derived from that member's unique compiled
  code, never a shared monolith or aggregate.
- **S0-I03 HONEST-SURFACE:** the source-to-obligation manifest binds every
  family member to its role's cost-bearing calls and transitions.
- **S0-I04 ANTI-STUB-CAN-FAIL:** the hollow control demonstrably fails while
  the real skeleton manifest passes.
- **S0-I05 PIN:** path, version output, and freshly recomputed binary digest
  agree with S0-R07.
- **S0-I06 ARITHMETIC:** byte count is even-hex-length divided by two; both
  percentages and both headrooms are recomputed from the bytes.
- **S0-I07 THRESHOLD:** 12,907 bytes or more receives `REDESIGN`; 12,906 bytes
  or less does not.
- **S0-I08 CAVEAT:** no size verdict is promoted to transaction-fit evidence.
- **S0-I09 EVIDENCE:** each claim is bound to captured output, exit status,
  source commit, blueprint hash, and toolchain hash.
- **S0-I10 SINGLE-BUILD:** overlapping ownership of the programme build token
  is impossible.

## Acceptance

S0 is complete only when all ten invariants have evidence, all seven rows are
present, every threshold breach is named for redesign, the hollow negative
control is recorded with non-zero exit, the real control and measurement exit
zero, and the final source is a clean local commit. No push or GitHub mutation
is part of acceptance.

