# NOTE-008 — RELEASE: frozen tree a67e3ed16. Finish the verdict.

Wake condition met: #373 merged (127f2e8, 23/23 incl. E2E re-run per #382);
#372 merged earlier. main = a67e3ed16d4f406fa99dd8b746a65e0c2c0b8359.

1. Resume in this root (interrupted run resumes here): read resume.md +
   this note first, then rebase worktree on a67e3ed16 via the git workflow.
2. Verdict scope: tree WITHOUT the retired lifecycle machinery.
3. Frozen hashes: RE-DERIVE against the frozen tree. Do not restate
   planning-boundary hashes — mismatch is a real finding, restatement is a
   defect. (Precedent in this lane: F-365-001.)
4. Honest limits carry: F-365-001 lineage (gate-v5 line-23 exit-127 found by
   submission-2 audit; branch merged at 127f2e8 with 23/23 green; re-cut
   #383 opened then closed superseded-by-merge, never dispatched), E2E
   timing race filed as #382, OD-366-001 (stale Aiken comment naming deleted
   Lean file, recorded not opened).
5. Out of draft, CI green, COMPLETE ready-for-review. No merge (project
   desk merges). Finite caps/preflight apply IF you seat any auditor; a
   pure-report finish needs none — state which in planning.

Acknowledge: NOTE NOTE-008 read. Then finish it.
