# Data model

Artifact ceiling: 2,000 bytes / 60 lines.

| ID | Data | Fields and invariants |
|---|---|---|
| D387-01 | declaration inventory | complete theorem identity, declaration kind and source span; nonempty; identities unique; current extent 87 with exactly 13 `Step.*_iff` identities |
| D387-02 | observed identity surfaces | declaration identities, checker-row identities, lamp occurrences and falsifier identities; every member retains its spelling including `.` |
| D387-03 | identity agreement | missing, unexpected and duplicate identities; PASS only when exact unique members agree, with lamp occurrence exactly one |
| D387-04 | control result | control ID, applied scratch mutation, expected diagnostic class, exit and observed diagnostic; mutation application is itself asserted |
| D387-05 | sweep row | path, line, extraction/comparison shape, classification (`repair`, `safe-domain`, `historical-evidence`, `out-of-scope-risk`) and disposition |

Counts are diagnostics over these identities, never substitutes for D387-03.
