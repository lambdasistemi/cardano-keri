# Issue 383 implementation plan

Artifact ceiling: 4,000 bytes / 100 lines.

## Strategy

Treat F-365-001 as an acceptance-instrument defect. Freeze v6 from retained v5
with the exact one-byte comment insertion and prove each v6 predicate can fail.
Campaign-031 exposed a second executability defect: receipt hashing included an
absolute worktree path. Under A-002, repair that construction minimally, prove
both relocation acceptance and content-change rejection, regenerate receipts,
then spend one additional full campaign through unchanged v6.

## Ordered slices

1. **S383-P1 Contract.** Bind current main, the `127f2e8` campaign-subject
   manifest, v5 identity, retained campaign-030 hashes, invariants, and budgets.
2. **S383-P2 Gate freeze.** Create ignored/root and runtime v6 copies, prove the
   exact one-byte v5-to-v6 delta, freeze the hash, and execute all per-leg RED
   controls including line-66 reachability with zero mutation builds.
3. **S383-P3 First execution.** Retain campaign-031's GREEN body and terminal
   receipt-comparator failure; it is evidence, not an accepted gate run.
4. **S383-P4 Portable receipts.** A fresh alternate-family owner changes only
   the runner digest construction and generated receipts, proves both control
   directions, and runs the sole A-002 full campaign through unchanged v6.
5. **S383-P5 Audit.** Fresh family-eligible auditors check the exact candidate
   and all invariant rows without rerunning the full campaign.
6. **S383-P6 Finalization.** Stamp accepted tasks, create the final commit,
   mechanically verify subject/tree identity and compact receipts, push, wait
   for green remote CI, pass finalization audit, and mark the draft ready.

## Execution accounting

- Full post-ruling v6 campaigns: campaign-031 is spent and terminal; A-002
  authorizes exactly one additional full campaign.
- Per-leg controls: finite ledger established before execution; zero controls
  may perform a mutation build except the single authorized GREEN campaign.
- Audit launches: one initial fresh seat plus one aggregate corrected redispatch
  only for a demonstrated commissioning defect; no findings repair bounce is
  authorized because #365 already exhausted submission 2.
- Auditor full-campaign executions: 0.

## Failure visibility

Controls capture command, exit, intended diagnostic, subject identity, and
output hash. A nonzero exit with no row identity is setup evidence, not a
semantic kill. The success path must emit the 79/79, 20/20, identity,
wrong-reason, blocked, build, axiom, pre/post, receipt, and final GREEN signals.

## Constraints

The ticket owner owns the mandate, v6 and control contract. The A-002 commit
owner owns the minimal runner/receipt repair and sole additional full run. The
auditor is read-only.
No role may edit the production/model subject or witness/sensor content named by
R383-01. A-002 permits only the runner digest and two generated receipts.
Campaigns 030 and 031 remain retained with their distinct historical outcomes.
