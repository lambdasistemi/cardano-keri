# Issue 383 — executable semantic-atom acceptance gate

Artifact ceiling: 6,000 bytes / 140 lines.

## Outcome

A release custodian can execute frozen gate-v6 and observe the complete
semantic-atom campaign run through its runner, finish GREEN, and carry a fresh
independent PASS that closes F-365-001 without changing the campaign subject.

## Requirements

- **R383-01 Candidate identity.** The #365 production/model subject and all
  witness/sensor content remain byte-identical to candidate
  `127f2e8794d65987f3405610be30385992d4dd09`:
  `lean/CardanoKeri/{Checkpoint,CheckpointGoals,Registry,RegistryGoals,Cage,Samaritan}.lean`,
  `lean/SEMANTIC-ATOMS.md`, `lean/mutants/mutants.txt`, and all tracked sensors
  and witnesses. A-002 permits only the exact runner digest repair and its two
  regenerated receipt outputs. Later reports and documentation are outside
  this subject.
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
- **R383-05 Full execution.** Campaign-031 consumed the A-001 launch: its body
  was GREEN but v6 rejected a path-bound generated receipt. A-002 authorizes
  exactly one additional full campaign after the minimal receipt repair. It
  runs through frozen v6 without shortened legs and reports
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
  specification, sensor, or witness content change is permitted. A-002 extends
  scope only to making the runner's witness/sensor digest independent of the
  absolute worktree path and regenerating the two tracked receipts. A
  subject-byte mismatch remains `SCOPE-FAIL`.
- **R383-09 Relocation control.** The digest/receipt check accepts identical
  witness+sensor bytes in distinct worktree paths and still rejects changed
  bytes at one path. A repository scan records every filename-bearing digest
  construction of the same class within the declared runner/receipt scope.

## Invariants

- **INV-383-SUBJECT:** every frozen production/model/witness/sensor path equals
  `127f2e8`; only the A-002-authorized runner and receipt paths may differ.
- **INV-383-GATE:** v6 differs from v5 by exactly the single comment byte and
  every consumer executes the hash-bound v6 copy supplied in its own lane.
- **INV-383-REACH:** a can-fail control proves v6 enters `run.sh --run` and the
  runner reports v6's resolved path/hash before refusing its zero build budget.
- **INV-383-LEGS:** every gate predicate has an executable, intended-reason
  negative control; silence or an unrelated earlier failure closes no row.
- **INV-383-CAMPAIGN:** campaign-031 remains terminal evidence of a GREEN body
  and receipt-comparator failure; exactly one A-002 campaign then satisfies
  every conjunctive R383-05 gate outcome.
- **INV-383-PORTABLE:** the witness/sensor digest and generated receipts are
  invariant under repository relocation but sensitive to a content mutation.
- **INV-383-RETAIN:** campaign-030's retained bytes and hashes are unchanged
  and labelled historical supporting evidence.
- **INV-383-AUDIT:** the exact tracked candidate plus frozen v6 and evidence
  receives a fresh independent PASS with zero blocking findings or residuals.

## Acceptance

All invariants pass, the A-002 full v6 execution is GREEN, the auditor reports
PASS with zero residuals, the final tree changes only this mandate and the
supersession/runner/generated-receipt repair, remote CI is green, and the PR is
ready for review. The ticket owner does not merge.
