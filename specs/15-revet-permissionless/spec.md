# Spec — Re-vet the canonical permissionless model (#15)

## Problem

The architecture was redesigned twice since the original vetting (oracle-controlled
per-company registry → current **canonical permissionless model**). The analyses in
`docs/vetting/` target `aid-ops.md`, an archived spec. The current normative docs
(`docs/architecture/`, `docs/design/`, `docs/design/business-cases/`, `docs/roadmap.md`)
have **never been independently vetted**. Vetting gates M1 implementation per the
design-first rule — in particular #24, whose on-chain `trie_key` shape is frozen at v1.

## P1 user story

As the team about to implement M1, I need an independent adversarial review of the
current design so that soundness/consistency defects are found and filed **before** the
irreversible on-chain shapes are committed.

## Method (mirrors the original two-pass vetting)

1. **Two independent cold passes** over the current normative docs, different primary
   lenses (soundness/attack-surface; consistency/completeness), each producing a report
   under `docs/vetting/`.
2. **Cross-examination**: reconcile, dedupe, and adversarially verify each finding
   (drop the ones that don't survive scrutiny).
3. **Merged findings table** by severity with status, added to `docs/vetting/index.md`
   (kept clearly separated from the historical aid-ops findings).
4. **File surviving findings as GitHub issues**, milestoned/blocking as appropriate
   (Critical/High that touch #24's frozen shapes block #24).

## Success criteria

- Both pass reports committed under `docs/vetting/`.
- A merged, deduplicated, severity-ranked findings table in `docs/vetting/index.md`
  scoped to the current model (not the archived spec).
- Each surviving Critical/High finding is a filed issue, linked from the table, with any
  #24-blocking ones marked as such.
- No design-doc content is changed in this PR — vetting **produces findings**, it does not
  fix them (fixes are follow-up tickets).

## Out of scope

- Fixing the findings (separate tickets).
- Re-vetting the primers or the archived `aid-ops-historical.md`.
