# Plan — Re-vet the canonical permissionless model (#15)

## Method

Two independent cold passes (different lenses) → cross-examine → merged severity table
→ file surviving findings as issues. Mirrors the original two-pass vetting.

## Slices

### S1 — vetting reports + merged findings (docs only)
- `docs/vetting/analysis-2-soundness.md` — Pass A (soundness / attack surface).
- `docs/vetting/analysis-2-consistency.md` — Pass B (consistency / completeness).
- `docs/vetting/canonical-model-findings.md` — merged, deduplicated severity table
  (F1–F32), cross-confirmation marks, `blocks #24` tags, two structural themes.
- `docs/vetting/index.md` — round-2 pointer above the historical summary.
- Gate: `mkdocs build --strict` + lychee link check pass; no normative design doc changed.

### S2 — file findings as issues (post-review)
- After operator triage, file surviving Critical/High as issues; mark `blocks #24`
  ones as blocking; add each to the planner. Link issues back from the findings table.

## Out of scope
- Fixing any finding (separate tickets).

## Gate
- Docs build strict green; `git diff` touches only `docs/vetting/**` and `specs/**`.
