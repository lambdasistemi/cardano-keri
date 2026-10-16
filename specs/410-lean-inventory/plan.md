# Produce a reproducible inventory

A reviewer receives a compact overview and machine-readable records bound to the frozen tree, plus independent evidence that omissions and identity substitutions fail.

## Decisions

| Choice | Alternative left out | Reason |
|---|---|---|
| Inventory the exact frozen subject | Refreshing main | The release is revision-specific. |
| Discover declarations through imported compiled environments | Grep or count-only comparison | Names, origin modules and proposition/proof metadata must reconcile exactly. |
| Retain historical evidence by immutable path and hash | Rewriting baseline outputs or presenting them as fresh | Preserve the attack record and its limitations. |
| Ship a narrowly scoped inventory verifier | A new design runner | Runner ownership and release integration remain unbound. |

```mermaid
flowchart LR
    Baseline["Existing library checks"] -->|"establish source baseline"| Gate["Frozen inventory gate"]
    Gate -->|"independent gate review"| Owner["Alternate-family commit owner"]
    Owner -->|"frozen candidate"| Review["Fresh independent review"]
    Review -->|"exact head and receipts"| PR["Draft inventory PR"]
```

## One bounded slice

The commit owner owns only `docs/design/lean-invariants-inventory/**` and `scripts/check-lean-invariants-inventory.py`. The ticket owner owns only this planning directory and ignored runtime gates. No source behavior changes. No publishing, merging, comments or reviewer pings. Draft PR creation and scoped branch push are authorized.

The declared inventory denominator is the complete union of declarations whose original compiled module is `CardanoKeri` or lies below `CardanoKeri.`, loaded through both existing roots. Baseline observation is 3293 declarations across 19 origin modules. The fresh set, not that count alone, is the authority. Sources include all tracked `lean/`, `simulator/`, watcher-conformance evidence and named design/toolchain inputs. The historical runtime sources recorded by existing manifests remain distinct from the current subject.

Verification runs the preserved traceability script, then explicitly builds both libraries and extracts/reconciles the compiled extent. Inventory mutants alter records after extraction, so compilation failure cannot masquerade as a missing-record kill. The inventory check is a reproducible CLI separate from production gates. Appropriate existing docs checks run for the final diff; unrelated baseline failures are attributed without repair.

## Resource bounds

Planning files: at most 100 lines and 10 KiB each; compiled worker brief at most 200 lines and 20 KiB. Inventory output at most 20 MiB; checker and extraction helper together at most 1000 source lines. Gate review: one blind Grok seat, one author repair batch maximum, two launch attempts maximum. Implementation uses one GLM commit owner, no draft. Candidate review uses two blind Codex inspectors on submission one and one delta inspector on submission two; at most one aggregate corrected redispatch per submission. Concrete execution allocations and wall ceilings are frozen in runtime before each campaign. No third submission, budget increase, new campaign or new ticket without parent release.
