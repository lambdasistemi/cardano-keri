# S0 implementation plan

Artifact ceiling: 7,000 bytes / 150 lines.

## Strategy

Create a measurement-only Aiken family under a new namespace. Shared types and
small reusable operations live in library modules; the blueprint exposes seven
separate validators so compiled code is independently observable.

Staging is Tx-A (1024-byte Blake3 SAID premint + burn). Append/cursor are
Tx-B (total-parse + token burn + transition). The skeleton boundary is the
cost-bearing surface, not complete S2 behavior.
Each role must retain the representative parsing, cryptographic/proof,
transaction-context, and state-transition operations listed in the modules
model. Explicit comments identify obligations, while the independent audit
confirms that the named operations are reachable from the measured handler.

The predicate library is measured through a dedicated validator whose handler
invokes the complete four-dimensional predicate over keys, state, grade, and
freshness. The reference consumer is distinct: it locates/decodes a cursor-like
reference input and invokes the library predicate.

## Ordered slices

1. **S0-P1 Contract and gate.** Freeze this mandate and a runtime anti-stub /
   measurement gate. Demonstrate the hollow fixture fails.
2. **S0-P2 Skeleton family.** Add shared types, the predicate library, and all
   seven reachable validator programs without implementing S2-complete rules.
3. **S0-P3 Measurement.** Build once under the programme token, validate the
   blueprint cardinality, emit each bare verdict immediately, and generate the
   complete report and evidence bundle.
4. **S0-P4 Audit and acceptance.** Audit the exact local candidate from a fresh
   detached worktree, then mechanically verify the accepted commit and report
   every threshold breach upward.

## Live boundaries and limits

- Compiler: pinned Aiken v1.1.23 store binary and digest from `spec.md`.
- Compiler commands require a pseudo-TTY.
- Build ownership: `/tmp/ms-keri-11/BUILD-TOKEN` with the 53.10 GiB start and
  50.00 GiB stop floors.
- Reference-program ceiling: 16,133 bytes.
- Transaction-size comparison: 16,384 bytes.
- Redesign trigger: strictly greater than 80% of 16,133 bytes.
- Runtime evidence lives under `/tmp/ms-keri-11/s0-owner/`; reproducible source,
  harness, and report live in the repository.
- Tx-A inherits the 1024-byte premint cap; 1049-byte 8-key icp is refused
  before append. Do not reuse `g1_c4_input_393` / `g1_c4_input_966`.
- Co-residency: Tx A = staging_proof_token mint; Tx B staged event =
  append + cursor + staging_proof_token burn; fully-witnessed premium
  adds maintenance_escrow. Lineage/consumer paths reference record or
  cursor rather than execute them. Sum 25,617 B is
  `CO-RESIDENCY-UNRESOLVED witness_mode=UNSPECIFIED`: no S0 Tx-B
  builder chooses inline vs reference. NOTE-006 FAIL is superseded.
  Single-token burn coupling is a skeleton artifact. M1 established
  pattern is REFERENCE; that does not select S0 Tx-B witnesses.
  Named S2 handoff: `S2-HANDOFF-CO-RESIDENCY-WITNESS-MODE`. The
  per-script gate cannot discharge this. No new decomposition.
- M1 artifacts are read-only inputs. S2 behavior, preprod, mainnet, release,
  push, PR, issue, and authenticated GitHub mutation are forbidden.

## Verification

The frozen S0 gate owns the focused proof. It validates source obligations,
toolchain identity, blueprint cardinality, metric arithmetic, caveat presence,
the anti-stub negative control, and the final report. A fresh auditor reruns it
against the exact candidate. The ticket owner runs the same gate through a
hash-bound receipt before accepting the final local commit.

