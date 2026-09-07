# Data model — #368 hash-bound Lean audit report

Artifact ceiling: 100 lines.

## DAT-368-RELEASE — merged-base release

- `commit`: exact Git commit published by the epic owner.
- `answer`: durable answer path and content hash.
- `parents`: merge ancestry evidence for #363 through #366.
- Invariant: no audit execution precedes admission of this record.

## DAT-368-INPUT — audited-input manifest

- One sorted row per tracked audited path: Git mode, Git blob hash, path.
- Extent: every tracked `lean/` path except `lean/AUDIT-REPORT.md` and
  `lean/audit-evidence/**`.
- `digest`: SHA-256 of the exact manifest bytes.
- Invariant: report digest, evidence-directory name, frozen manifest digest,
  and final recomputation are equal.

## DAT-368-ROW — audit matrix row

- `id`: stable ruling, inversion, theorem, semantic-atom, or correspondence ID.
- `source`: authoritative ruling/model/theorem site.
- `severity`: blocking or advisory.
- `operator`: applicable finite mutation/checker operator.
- `status`: closed, killed, proved, refuted, open, blocked, withdrawn, or N/A
  as constrained by the row class.
- `evidence`: digest-bound pointer into MOD-368-EVIDENCE.
- `limit`: what this result does not establish.

## DAT-368-FINDING — unresolved audit result

- `row`: violated DAT-368-ROW ID.
- `evidence`: hash-bound pointer.
- `failureClass`: structural, semantic-atom, proof-trust, refutation,
  correspondence, provenance, scope, or contract.
- `limit`: precise epistemic boundary.
- `blocking`: yes or no with mandate basis.
- Invariant: contains no repair instruction.

## DAT-368-RECEIPT — command evidence

- Exact command digest, start/end or duration, exit status, stdout/stderr
  content hash, byte/line counts, and durable path.
- Mutant receipts additionally bind one intended edit, compilation, checker
  reach, intended failure reason, wrong-reason exclusion, and restored tree.
