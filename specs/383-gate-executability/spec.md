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
  and witnesses. A-003 permits only the runner's derived-relative digest and
  exact axiom-identity account repairs plus their two regenerated receipt
  outputs. Later reports and documentation are outside this subject.
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
- **R383-05 Full execution.** Campaigns 031 and 032 remain retained with their
  distinct outcomes. A-003 authorizes exactly campaign-033 after both audit
  findings are repaired. It runs through unchanged frozen v6 without shortened
  legs and reports
  79/79 atom kills, 20/20 reached+killed theorem rows, identity SURVIVED,
  wrong-reason 0, blocked 0, at most 210 builds, clean axiom account with no
  `sorryAx`, byte-identical generated receipts, empty pre/post input diff, and
  a final full `lake build`.
- **R383-06 Historical retention.** Campaign-030 remains unchanged historical
  evidence. Its hashes are recorded but it is not called the v6 GREEN run.
- **R383-07 Independent audit.** Submission 2 uses two fresh blind inspectors
  in detached clean worktrees at the exact tracked candidate. They verify the
  candidate manifest, gate identity, control ledger, retained campaigns and
  campaign-033 without running a full campaign or Lean build.
- **R383-08 Scope.** No production Lean model, semantic-atom ledger, mutant
  specification, sensor, witness, theorem-statement or gate-v6 content change
  is permitted. A-003 extends scope only to deriving repository-relative
  witness/sensor names, exact unique dotted axiom identities, and regenerating
  the two tracked receipts. A subject-byte mismatch remains `SCOPE-FAIL`.
- **R383-09 Relocation control.** The digest/receipt check accepts identical
  witness+sensor bytes at a direct path and two distinct symlink paths and
  still rejects changed bytes at one path. Relative names are derived by
  construction, never by prefix subtraction.
- **R383-10 Axiom identity control.** The generated account preserves complete
  dotted theorem names and requires exact unique identity agreement. A
  same-count substitution must fail for the intended identity reason.
- **R383-11 Extension stopping rule.** If audit submission 2 finds another
  acceptance instrument that passes without checking what it claims, stop
  without repair and re-cut redesign as a separately mandated ticket.

## Invariants

- **INV-383-SUBJECT:** every frozen production/model/witness/sensor path equals
  `127f2e8`; only the A-002-authorized runner and receipt paths may differ.
- **INV-383-GATE:** v6 differs from v5 by exactly the single comment byte and
  every consumer executes the hash-bound v6 copy supplied in its own lane.
- **INV-383-REACH:** a can-fail control proves v6 enters `run.sh --run` and the
  runner reports v6's resolved path/hash before refusing its zero build budget.
- **INV-383-LEGS:** every gate predicate has an executable, intended-reason
  negative control; silence or an unrelated earlier failure closes no row.
- **INV-383-CAMPAIGN:** campaigns 031 and 032 retain their exact outcomes;
  campaign-033 alone is the A-003 acceptance run and satisfies every
  conjunctive R383-05 gate outcome.
- **INV-383-PORTABLE:** the witness/sensor digest and generated receipts are
  invariant at direct and symlink-reached repository paths but sensitive to a
  content mutation; no prefix subtraction participates.
- **INV-383-AXIOMS:** the clean account contains exactly 210 unique intended
  theorem identities, including all thirteen `Step.*_iff` declarations, and
  contains no `sorryAx`.
- **INV-383-RETAIN:** campaign-030's retained bytes and hashes are unchanged
  and labelled historical supporting evidence.
- **INV-383-AUDIT:** the exact tracked candidate plus frozen v6 and evidence
  receives a fresh independent PASS with zero blocking findings or residuals.

## Acceptance

All invariants pass, campaign-033 is GREEN through unchanged v6, both
submission-2 inspectors report PASS with zero residuals, the final tree changes
only this mandate and the supersession/runner/generated-receipt repair, remote
CI is green, and the PR is ready for review. The ticket owner does not merge.
