# Delivery plan

## Bound authority

Base: 5a35284be464a3706df4093ebc67ea64f33e65a4. Branch docs/332-checkpoint-and-poison in its existing issue worktree. One OWNER documentation slice; ticket owner writes planning/gates, alternate visible commit owner writes the note, fresh visible independent audit follows. Draft NONE. At most two audited submissions and one adjudicated repair. No extra review hierarchy.

Frozen accepted source: `/tmp/projects/cardano-keri/owner/handoffs/M1-RETURN-audit-and-plan-2026-09-02.md`, sha256 `84a8ea08dba82f3240004002b5ce4dce13401f3a9e72fcfb4bef2f8416c712a1`. Its D-039/D-040 addendum supersedes earlier pause/withdraw/terminal-close descriptions.

Governing epic answer: `/tmp/ms-keri-1/epic-318/answers/A-001-registry-rulings-diverge.md`, sha256 `6583d9b4fc4e920bf2ae3cca412b6697131b75c8c6b77cd794c8b09379c2eab5`. The task brief and subsequent ticket answer A-001-additional-gap-issue-coverage govern scope and unresolved-question classification. Parent amendments must be read and acknowledged, not inferred from source prose.

Historical retained clarity: `/tmp/projects/cardano-keri/owner/.archived/commit-owner-slice3-fable/handoffs/LEAN-CLARITY.md`, sha256 `53bcfdfdbfddff47e8ee2b8e79cf52dfacbd2ee7bc4dc344767f4b33ff12f1c5`. Historical evidence only; #333 owns entry disposition.

## Source horizon

Checkpoint.lean/CheckpointGoals.lean and Registry.lean/RegistryGoals.lean at the base, both simulator cores and clauses, simulator/M1-STORIES.md, REGISTRY-LEAN-CLARITY.md and README.md. Reader references: DN001, key-compromise, registry-as-mpfs, roadmap and mkdocs.yml. Current code is semantic evidence; historical prose cannot override the accepted rulings.

Refresh before acceptance: origin/main movement, PR identity, #332/#318/#408/#358/#359 statuses, source-story #418 status, relevant upstream issue status, CI and meaningful served page/speech bytes. No automatic rebase or source retargeting.

## Ordered work

1. Preserve the one running clean-base full CI invocation; record its outcome and pre-existing failures separately. Complete compact mandate and ignored gate; open draft PR before document implementation.
2. Freeze gate, failure-class controls, source hashes, finite review/launch budgets and worker packet. Apply the required independent gate review within the declared topology.
3. Owner writes DN003 and speech, optional nav and narrow supersession notices plus speech. A runtime correspondence map ties each invariant to exact declarations/sections and open issues; semantic review checks omissions as well as incorrect statements.
4. Independent document review of the frozen candidate, rendered presentation, source correspondence, gates and scope. One repair batch only if needed; fresh review of repaired SHA.
5. Final mechanical verification, push, CI and preview-byte identity; record the separately owned #418 correction status before readiness. Report review request and residual operator acceptance. No merge.

## Checks

The immutable ticket gate includes git diff --check; the repository presentation command for every changed Markdown page; strict MkDocs; lychee with fragments and the exact brief options; current Docs CI architecture checks; full local CI using the pinned just invocation. Bare Python is absent: run the unchanged presentation tool in a Nix Python environment. No root flake exists. Raw logs remain outside Git and only compact exit/duration/hash receipts enter supervision.

Semantic truth is not mechanically entailed by a document build. A missing/incorrect ruling remains a review failure even with green checks. Baseline failures do not authorize tooling or production fixes in this ticket.

## Output ceilings

Each planning artifact: at most 120 lines and 12 KiB. Combined six artifacts: at most 24 KiB. Each child brief: at most 160 lines and 16 KiB, excluding hash-bound references. DN003 target 1500–2500 words; exceeding that requires a specific readability reason in the owner receipt, not a new product scope. Keep one readable idea per diagram. Runtime maps and evidence are not reader prose.

Parent amendment NOTE-002 / epic A-002: #418 owns three checkpoint-story corrections and the coupled story-12 clause classification. Link it while open; use corrected meanings now. Its #390 gate dependency is outside #332. Retraction receives a descriptive link to the existing registry design discussion, without reopening the debate. #318 acceptance includes #418, but this ticket continues independently.
