# Issue 383 data model

Artifact ceiling: 3,000 bytes / 80 lines.

| ID | Shape | Fields and invariants |
|---|---|---|
| D383-01 | subject row | Git mode, blob, path, reference candidate blob; complete sorted extent, no duplicates, every row equal |
| D383-02 | gate identity | version, path, SHA-256, predecessor SHA-256, exact binary diff; v6 delta is one inserted `#` only |
| D383-03 | control row | stable leg ID, exact predicate/failure class, mutated disposable input, expected exit/diagnostic, observed exit, output hash; every row must reject |
| D383-04 | campaign identity | gate path/hash, source commit, ledger/runner/spec hashes, start/end, build count, summary and raw-output hashes |
| D383-05 | campaign result | atom total/killed, theorem total/reached/killed, identity result, wrong-reason count, blocked count, stopping reason, pre/post status, axiom count and `sorryAx` count |
| D383-06 | retained evidence | campaign-030 path and hashes, historical label, immutable-byte comparison result |
| D383-07 | audit result | candidate, packet/report hashes, invariant matrix, execution count, verdict, blocking findings and residual count |
| D383-08 | portable file-set digest | sorted repository-relative filename plus content hash; equal across checkout roots, unequal after a member's byte mutation |

An absent, empty, duplicate or truncated extent is failure. Historical and new
campaign identities never collapse into one result.
