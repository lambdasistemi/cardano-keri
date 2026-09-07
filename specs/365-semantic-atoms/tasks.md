# Issue 365 tasks

Artifact ceiling: 3,000 bytes / 80 lines.

## S365-P1 — frozen contract and gate

- [x] **T365-01** Freeze the compact mandate, semantic-atom ledger, theorem-row
  inventory, and finite operator/budget/stopping contract at `9b2e6b8`.
  (v3 supersession `lean/mutants/FREEZE-SUPERSESSION.md`: v1 ledger
  `925da196…`, v2 ledger `3c1d0c22…`, 79 atoms / 20 rows, ceiling 210.)
- [x] **T365-02** Freeze and falsify the runtime gate for inventory/campaign,
  build, and axiom evidence classes.
  (gate-v1 `68426237…` preserved; gate-v2 `bddf56d6…` + gate-v3 `e5b34034…`
  versioned with supersession; 34/34 v2 predicate controls PASS
  `handoffs/v2freeze/` plus multiline validator deletion controls
  `handoffs/v3freeze/`.)

## S365-P2 — mutation campaign

- [x] **T365-03** Extend the isolated runner and mutant specifications across
  the complete frozen Checkpoint/Registry/Cage/Samaritan atom extent.
  (84 specs: 79 atoms + 5 AUX; campaign-027 79/79 KILLED right-reason.)
- [x] **T365-04** Add reachable witnesses and sensitivity kills for every
  compiled Cage/Samaritan theorem row.
  (campaign-027 20/20 REACHED+KILLED: 13 shared + TH-06 AUX + 4 sensor AUX +
  TH-19/20 via additive atom kills.)
- [x] **T365-05** Regenerate both receipts from one raw run with identity,
  exclusions, structural discounts, separate denominators, and honest limits.
  (`lean/CHECKPOINT-MUTANTS.md`, `lean/REGISTRY-MUTANTS.md` byte-identical to
  campaign-027 receipts: 79/79, 20/20, 0 excluded, 0 blocked, 197 builds.)

## S365-P3 — independent acceptance

- [ ] **T365-06** Obtain a fresh alternate-family audit of the exact candidate
  over INV-365-DENOMINATORS through INV-365-AXIOMS.

## S365-P4 — merged-base rerun and delivery

- [x] **T365-07** Consume the epic-owner C1+C2 merged-base release, rebase via
  the git workflow, and mechanically rerun the entire campaign and axiom/build
  checks so receipts bind the merged commit.
  (base `370a23b…`, HEAD `16f7a5b3…`, campaign-029 GREEN 79/79 + 20/20,
  receipts name the base, 197/210 builds.)
- [ ] **T365-08** Accept the final audited tree, create the final commit, push
  the exact SHA, wait for green CI, pass finalization audit, and mark the draft
  PR ready for review without merging.
