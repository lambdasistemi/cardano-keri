# Data model

Artifact ceiling: 2,000 bytes / 60 lines.

| ID | Data | Fields and invariants |
|---|---|---|
| D387-01 | declaration inventory | complete theorem identity, declaration kind and source span; nonempty; identities unique; current extent 87 with exactly 13 `Step.*_iff` identities |
| D387-02 | derived identity classes | proof-only identities are exactly `Step.<constructor>_iff` joined to constructors derived from the Lean `Step` inductive; observable identities are the complement; classes are disjoint and exhaustive |
| D387-03 | class identity agreement | 74 observable declarations agree exactly with checker rows, lamp occurrences and falsifiers; 13 proof-only declarations agree exactly with the constructor-derived inversion set; reject missing, unexpected and duplicate members; observable lamp occurrence is exactly one |
| D387-04 | control result | control ID, applied scratch mutation, expected diagnostic class, exit and observed diagnostic; mutation application is itself asserted |
| D387-05 | sweep row | path, line, extraction/comparison shape, classification (`repair`, `safe-domain`, `historical-evidence`, `out-of-scope-risk`) and disposition |

Counts are diagnostics over these identities, never substitutes for D387-03.
The proof-only class records, but does not close, absent simulator observability.
