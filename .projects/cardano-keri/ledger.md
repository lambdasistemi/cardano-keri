# cardano-keri project ledger

Swept 2026-09-02 by project owner pane `%254`, session `0-projects`, window
`cardano-keri`. Supersedes the 2026-09-01 snapshot.

## Project definition

`cardano-keri` is the product line for projecting KERI control-state evidence
onto Cardano and making that projected state consumable by Cardano scripts and
applications. It remains an **architectural experiment** until its named gates
and its external product gate pass. No mainnet, production rollout,
announcement, or external commitment follows from an experiment result.

Direction of the arrows is a standing constraint: cardano-keri **projects** what
GLEIF/QVIs already publish (KEL plus mandated public TELs). It never requires
KERI-side parties to do anything new. The poison declaration (below) is the one
Cardano-native act a controller may perform; it needs only stock `kli sign`.

## Ordered milestone map

| Product milestone | GitHub | Lifecycle | State as of 2026-09-02 | Desk |
|---|---:|---|---|---|
| M1 — identity core | 1 | **RESUMPTION PLANNED**, Phase 0.2 done (was custodial-terminal, D-001) | Lean machine proved on PR #313; GLM simulator audited FINDINGS and stood down (PR #314 kept for disposition); the simulator follows the second Lean slice (D-036, D-037, D-038) on `feat/m1-simulator` (draft PR #315, preview live, self-published by the operator-driven seat); slice 2 accepted at `a892832` (62 theorems, three audits); the M1 plan v2 published; milestone 1 reopened with epics #318–#330 and tickets #332–#357; milestones 11 and 12 closed; #313, #315, #317, #360 merged (the machine, the simulator, the registry model, slice 3); D-036 to D-041; open: #355 docs, #358, #361, #362. The deployed V1 family (five preprod reference scripts, manifest 2026-07-28) is the checkpoint half of the target design. D-001 stands for the monolith only. The return plan `AUDIT-M1-RETURN` is delivered and awaits the operator's ruling on A1–A8. GitHub milestone still closed; description stale. 15 residual issues, dispositions proposed in the plan. | none yet — to be founded on acceptance |
| M1.2 — decomposed record+cursor | 11 | **RETIRED 2026-09-02** (D-021) | Founded on a constraint, not a purpose; converged back on the checkpoint. Outcome preserved below. Desk paused, unread retirement note in its inbox; session not yet retired. | `%103`, `keri-m12` — pending retirement |
| M1.3 — on-chain witnessing | 12 | REGISTERED ONLY | Premise is receipts over a record; the plan proposes re-scoping to the pen construction and chain-gated receipting against the checkpoint. Witness gating itself is already M1's rule. | none |
| M8 — Plutus Blaster | 8 | **PARKED** (revisit: first M1-line slice merged, or 2026-09-30 — D-013) | Holding #289's finished campaign, candidate `c424930` pushed. No session. | none — needs restoration |

M7/M1bis delegation and credential state remains a named future boundary.
Milestones 7 and 10 are registered backlog.

## The design the M1 line returns to

Checkpoint + poison + no interactions (DN002 §2/§4/§6/§7, audited in
`AUDIT-M1-RETURN`): one UTxO per AID holding current key state; advance only by
`rot` with the controller's dual threshold and witness receipts at `toad`
against the witness set; a **poison** — a signed declaration by the current
keys at `cur_threshold` over `policy_id ‖ cesr_aid ‖ native_sn`, stored as a
**bit that any witnessed rotation clears** (operator ruling 2026-09-02: next
keys are control; the poison is local to the current keys and cannot taint the
next keys); a close marker is a Phase 3 decision, not a requirement; the live machine has
exactly two edges, rotate and poison (D-022), both at the current threshold
(D-023), and cannot roll back; from the poisoned state only rotate is enabled,
so close is disabled while poisoned; an AID REGISTRY (one UTxO, one MPF root)
makes the token mint-once and queues inceptions (D-024), the token is never
burned, the checkpoint is permanent, pause keeps state and bond and is inert to current-key theft with
resurrection only by witnessed rotation (D-025, D-026, D-028), close is the
terminal exit for unpoisoned identities only, and a checkpoint is juvenile for W slots after register or a resurrecting
rotation; validity and refresh are the stated future direction (D-027), with
the fields reserved in the datum; freeze/seize are recommended out and the
witness-duplicity smoking gun is a TERMINAL conviction that seizes the bond in
full to the convictor's payee (D-030, D-031); freeze is gone; close pays the
refund address established at rotation (D-032); pause and resurrection are the
withdraw and deposit options of rotate, two edges in all (D-033); the hunter
economy — advance pool first, freeze bond when the pool is short, conviction
bond untouchable — is the design (D-034); `ixn`, `dip`, `drt` never
touch the chain; the tip never moves backward; no record tree, no occupancy, no
MPF fork, no enforcement economy. The differentiator survives as the poison
channel only. Everything about that design is proposed until the operator
rules on A1–A8.

## M1.2 outcome, preserved

S0 size fail-fast merged (PR #304); S1 harness executed; the projection-fidelity
design record merged (PR #301); the #300 requirements contract accepted at
submission 1 with zero repairs and 8/8 blocking rows killed; MPF bumped to
v2.1.0 closing two live `excluding()` correctness defects (PR #308); DESIGN
NOTE 002 (artifact 5cd434d8) — the reason the milestone was retired.
Inherited by the M1 line: DN002 §2, §3, §4, §6, §7. Dead with it: the record
tree, occupancy, the MPF fork and its upstream proposal, D-011, D-014, D-015,
D-016, D-017. PR #305 and PR #306 and issue #300 are orphaned and are closed
under the plan's Phase 4.

## The plan, in one paragraph

Phase 0 record (DN003, Lean checkpoint lifecycle, push `feat/291-inv-bind`,
surface-C mutations) → Phase 1 remove the enforcement economy in one reviewed
deletion, ending with a size table → Phase 2 land INV-BIND (#291) on the
slimmed tree under a re-versioned gate → Phase 3 poison, watermark, marker,
with the advance-vs-keripy parity oracle as the gate → Phase 4 retire the
M1.2 skeleton (parallel after Phase 0) → Phase 5 one preprod redeploy, the
stranger run with poison, `ckeri` 0.5.0. Preprod is redeployed once, at the end,
because every parameter or datum change makes a new register policy id.

## Project priority, from 2026-09-02

1. The operator's ruling on A1–A8.
2. Phase 0: the record before any code.
3. Push `feat/291-inv-bind` — the proven G0 repair is on one disk.
4. Found the M1 desk; retire the M1.2 session through the machine owner.
5. M8 at its revisit condition only.

## Cross-milestone inheritances

- M1 terminal steering package sha256
  `793bab01059d18bd8f9bd20fd9ec3e37b7454b06ea7bb20f87ec1b9ea3d56410`.
- G0: the decoder repair is proven against gate `7037228…` in both directions;
  it lives on `feat/291-inv-bind` (18 commits, base 2026-08-14, local only).
- G1 terminal result sha256
  `57585ae0c92d716b93b98c11addc16ee440bca9feca7f4b177b3f31423e85160`.
- A-019 mandate identities remain reachable via tag `ms11/mandates/a-019`;
  they bind nothing any more.
- The central monolithic checkpoint is not a candidate for anything.
- The product gate (one named pilot, one independent watcher with published
  time-to-record) remains outside every milestone.

## Open at sweep time — 2026-09-02

- **A1–A8** with the operator (see the plan §5).
- **Q-002 and Q-003 are CLOSED as overtaken**: the consumer question was
  answered underneath by the design session (no contract needs the evidence
  set; Story 7's treasury predicate reads a projection), which is what retired
  the tree.
- The unmerged `feat/291-inv-bind` — push pending any operator yes.
- The public account (gist 7615e40) and milestone 12's description describe
  the record; the operator's words, not an agent's.
- Withheld and unchanged: S3 and any preprod contact; surface-C mutations;
  mainnet, production, announcement, external commitment,
  delegation/credentials, product claims, the external product gate.

## Repository surface, 2026-09-02

`main` at `6902e33`. Open PRs: #311 (release 0.4.1), #306, #305, #290, #251.
Open issues 85 at the last sweep. Committed preprod manifest at `50a5820`
lists five scripts; `deriveV1Scripts` on `main` derives seven. `onchain/plutus.json`
is gitignored and stale. Three sweep worktrees (`/tmp/keri-sweep{,2,3}`) from
earlier ledger pushes are clean and removable.
