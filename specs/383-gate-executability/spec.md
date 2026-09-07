# Issue 383 — executable semantic-atom acceptance gate

Artifact ceiling: 6,000 bytes / 140 lines.

## Outcome

A release custodian can execute frozen gate-v6 and observe the complete
semantic-atom campaign run through its runner, finish GREEN, and carry a fresh
independent PASS that closes F-365-001 without changing the campaign subject.

## Requirements

- **R383-01 Candidate identity.** The complete #365 campaign subject remains
  byte-identical to candidate `127f2e8794d65987f3405610be30385992d4dd09`:
  `lean/CardanoKeri/{Checkpoint,CheckpointGoals,Registry,RegistryGoals,Cage,Samaritan}.lean`,
  `lean/SEMANTIC-ATOMS.md`, `lean/mutants/run.sh`, `lean/mutants/mutants.txt`,
  all tracked sensors and witnesses, and the two generated mutant receipts.
  Later mainline reports and documentation are outside this subject.
- **R383-02 Exact gate repair.** Preserve gate-v5 at SHA-256
  `10f06795bb5bb279a585466f4245ec0c10a28a4cc7c9ea07b0454a6d5e82719b`.
  Gate-v6 is v5 plus exactly one inserted `#` commenting former line 23; no
  other byte changes.
- **R383-03 Supersession.** Record v5 to v6 identities, the one-byte diff,
  F-365-001, and the reason a post-falsification edit creates a new gate.
- **R383-04 Per-leg falsification.** Before GREEN, execute negative controls
  for every gate predicate/failure class. Each control must fail nonzero for
  its named reason. A dedicated zero-build control must prove v6 reaches the
  line-66 `run.sh --run` call and binds the v6 path/hash.
- **R383-05 One full execution.** Exactly one new full mutation campaign is
  authorized. It runs through frozen v6 without shortened legs and reports
  79/79 atom kills, 20/20 reached+killed theorem rows, identity SURVIVED,
  wrong-reason 0, blocked 0, at most 210 builds, clean axiom account with no
  `sorryAx`, byte-identical generated receipts, empty pre/post input diff, and
  a final full `lake build`.
- **R383-06 Historical retention.** Campaign-030 remains unchanged historical
  evidence. Its hashes are recorded but it is not called the v6 GREEN run.
- **R383-07 Independent audit.** A fresh auditor, in a detached clean worktree
  at the exact tracked candidate, verifies the candidate manifest, gate
  identity, control ledger, retained campaign-030 hashes, and the sole v6 full
  execution. The auditor does not run a second full campaign.
- **R383-08 Scope.** No production Lean model, semantic-atom ledger, mutant
  specification, sensor, witness, generated receipt, or runner semantic change
  is permitted. A subject-byte mismatch is `SCOPE-FAIL` and requires a new
  campaign ticket, not a silent carry.

## Invariants

- **INV-383-SUBJECT:** the frozen subject manifest equals the same paths at
  `127f2e8` and remains equal at the submitted and final trees.
- **INV-383-GATE:** v6 differs from v5 by exactly the single comment byte and
  every consumer executes the hash-bound v6 copy supplied in its own lane.
- **INV-383-REACH:** a can-fail control proves v6 enters `run.sh --run` and the
  runner reports v6's resolved path/hash before refusing its zero build budget.
- **INV-383-LEGS:** every gate predicate has an executable, intended-reason
  negative control; silence or an unrelated earlier failure closes no row.
- **INV-383-CAMPAIGN:** one and only one post-ruling v6 full campaign exists,
  and its conjunctive result satisfies R383-05.
- **INV-383-RETAIN:** campaign-030's retained bytes and hashes are unchanged
  and labelled historical supporting evidence.
- **INV-383-AUDIT:** the exact tracked candidate plus frozen v6 and evidence
  receives a fresh independent PASS with zero blocking findings or residuals.

## Acceptance

All invariants pass, the single full v6 execution is GREEN, the auditor reports
PASS with zero residuals, the final tree changes only this mandate and the
supersession record, remote CI is green, and the PR is ready for review. The
ticket owner does not merge.
