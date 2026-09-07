# Issue 365 data model

Artifact ceiling: 4,000 bytes / 100 lines.

| ID | Shape | Fields and invariants |
|---|---|---|
| D365-01 | semantic atom | stable ID, ruling, exact model site, owning theorem set, severity; IDs are unique and blocking rows form a non-empty closed extent |
| D365-02 | mutant | stable ID, atom ID, target module, exact original blob/needle identity, replacement blob, operator; exactly one target occurrence and one semantic change |
| D365-03 | theorem row | fully qualified theorem, module, reachable witness ID, sensitivity mutant ID; inventory equals compiled Cage/Samaritan declarations |
| D365-04 | atom result | atom ID, mutant ID, compile status, killed/survived/blocked status, failing owning theorems, structural failures, exclusion reason, evidence hash |
| D365-05 | theorem result | theorem, witness reached flag/evidence hash, relevant mutant, killed flag/evidence hash |
| D365-06 | campaign identity | source commit, ledger hash, runner/spec hash, operator set, build budget, start/end, stopping reason, raw-log hash |
| D365-07 | receipt | generated campaign identity, independent totals for atom rows and theorem rows, identity result, exclusions, structural discounts, honest limits |

Equivalent or shadowed mutants are not kills. A result with a syntax/import/
setup failure, `sorryAx` crash, unrelated downstream failure, missing witness,
or target occurrence count other than one is excluded or `BLOCKED`.
