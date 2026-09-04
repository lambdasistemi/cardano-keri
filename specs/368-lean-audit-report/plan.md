# Plan — #368 hash-bound Lean audit report

## Constraints

Artifact ceiling: 180 lines. This ticket is the serial tail of epic #367. Its
current phase is planning only; the release-dependent phase cannot begin from
a sibling branch, local synthetic merge, or unmerged PR.

## Phase P0 — planning and park

1. Record the ticket-owner identity and pane in durable STATUS.
2. Open a draft PR from `issue-368-audit-report`.
3. Commit the six-file mandate, verdict-free report skeleton, and ignored
   planning gate; back the gate up under `/tmp/epic-367/to-368`.
4. Record gate and mandate hashes and `BLOCKED awaiting-merged-base`, then park
   without running Lean, mutation, axiom, or report-verification commands.

## Phase P1 — release admission and re-freeze

1. Read the epic owner's release from `answers/`; acknowledge it with
   `RESUMED` before acting.
2. Confirm the release names an exact commit containing the merged #363,
   #364, #365, and #366 ancestry. Stop through the epic owner on discrepancy.
3. Rebase the issue branch onto that exact commit using the governed Git
   workflow. Recheck branch, HEAD, status, and allowed paths.
4. Enumerate every tracked `lean/` input other than the report/evidence
   outputs. Freeze its path, Git mode, and blob hash in sorted order. Hash the
   manifest with SHA-256 and create only
   `lean/audit-evidence/<digest>/`.
5. Replace planning gate v1 with release gate v2, binding the released commit,
   input manifest, digest, commands, budgets, and expected receipts. Prove each
   gate failure class with frozen negative-control receipts before dispatch.

## Phase P2 — OWNER submission

Topology is OWNER because FULL Lean audit conclusions require semantic
judgment. Seat allocation is binding: ticket owner `codex` medium; commit owner
`muse` with exact non-Codex identity recorded at launch; fresh auditor `codex`
high for each submission; `draft=NONE`; maximum two audited submissions.

1. Compile the commit-owner brief from the released mandate and v2 gate. The
   owner may write only the report and digest-named evidence directory, plus
   its own runtime evidence; every other `lean/` path is read-only. No push.
2. Launch the owner in its own tmux pane and require a pane-bound post-cursor
   START. The owner audits the exact frozen tree, records raw hashed evidence,
   and submits a clean local candidate without repairing findings.
3. Park the owner write-idle. Create a fresh detached worktree at the candidate
   SHA and a new auditor runtime. Launch Codex high in a distinct pane and
   require its pane-bound START.
4. The auditor loads the `auditor`, `commit-auditor`, `lean4`, `invariants`, and
   `lean-auditor` contracts. It independently checks provenance, every
   invariant row, exact commands and evidence, semantics, limits, and the
   question: which failure modes did this report or evidence process alter,
   and are they still observable?
5. On first findings, forward only the immutable report/hash to the parked
   owner for the single licensed repair submission, then use a new audit pane,
   root, context, and detached worktree. Second findings stop the campaign.

## Phase P3 — acceptance and publication

1. Accept only a complete fresh audit matrix with no blocked mandate row.
2. Stamp the task file only after acceptance; have the commit owner create the
   final local commit. Mechanically prove it equals the audited candidate plus
   only the task stamp.
3. Run the v2 gate and repository-required checks through quiet hashed receipt
   recording on the exact final SHA. Recompute the audited-input digest and
   verify the report/evidence identity again.
4. Push the exact SHA, refresh the draft PR, wait for green remote CI, run the
   finalization audit, then mark ready. Do not merge.

## Evidence classes

- Release and Git ancestry/cleanliness receipts.
- Frozen input manifest and manifest-generation receipt.
- Full clean-`.lake` build and zero-escape scan.
- Theorem-qualified axiom inventory from the clean build.
- Live-derived inversion inventories and six checker self-falsifications.
- Theorem-row witness/mutant ledger and semantic-atom mutant ledger, including
  compile/reach/right-reason/tree-clean identities.
- Relation/function, Bool/Prop, replay, and simulator-facing correspondence.
- Gate negative controls, final gate, commit gate, finalization, and CI state.

## Stop conditions

Stop through the epic owner on missing/ambiguous release authority, scope
failure, gate dispute, a second failed audit, or any need to edit frozen Lean
inputs. Park rather than poll while awaiting release.
