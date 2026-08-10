# #246 functions model

New and changed named surfaces only: name, explicit inputs, result, and
signature-level constraints. No bodies, algorithms, or control flow.

## Slice A

| ID | Surface | Inputs | Result | Constraints |
|---|---|---|---|---|
| F-A1 | flake attribute producing the compatibility audit runner | locked upstream pin identities; tracked bridge source set; pinned upstream Lean packages | an executable taking no arguments | Takes no blueprint, program, or evidence input. Rejects any argument. Pin identities are read from the locked inputs, never passed in as literals. **Its resolution index is derived from Lean's own environment for the pinned packages — not from source-text pattern matching.** A resolution verdict must agree with the elaborator that builds those sources, in both directions. |
| F-A2 | tracked contract asserting the audit's own obligations | path to the audit executable; the tracked bridge source set | exit status; report on stdout | Exit non-zero if any reference is unresolved, any record is `COULD-NOT-EVALUATE`, the resolved count is zero, or a control's observed effect differs from its expected effect. |
| F-A3 | seeded retired-reference control artefact | the name to seed, absent at the declared pins | an input the audit consumes exactly as it consumes tracked bridge source | Owned by the control; must not alter any tracked Lean source's semantics, and must be consumed by F-A1 through the same path real source takes, so a control that bypasses the resolver is impossible. |
| F-A4 | changed blaster runner composition | existing extraction, production-source, pin-audit and S2 stages; plus F-A1 and F-A2 | exit status | The audit and both controls execute on every invocation of the single runner the gate calls. Existing stages keep their current order and meaning. |

## Slice B (declared, dispatched separately)

| ID | Surface | Inputs | Result | Constraints |
|---|---|---|---|---|
| F-B1 | baseline artifact producing the frozen blueprint at the anchor commit | tracked onchain source at the anchor; the Aiken version the repository validates with | the compiled blueprint | Reproducible from source rather than substituted by declared hash. Must not be routed into `checks.e2e`, `ckeriRunner`, or `packages.ckeri`. |
| F-B2 | manifest producer | F-B1's output; the declared title set | one record per D-05 | Every field computed from F-B1's output. Cardinality 23 titles / 8 distinct programs is asserted, not assumed. |
| F-B3 | variant-bound evaluation identity | the variant selected per D-04 | the identity every later record names | Names E explicitly. A version-derived selection is a distinct, separately named value and cannot silently stand in for it. |

## Slice C (declared, dispatched separately)

| ID | Surface | Inputs | Result | Constraints |
|---|---|---|---|---|
| F-C1 | bundle entry point | a fresh checkout at the anchor | the bundle contents and the announced triple | Depends on nothing outside the checkout and its declared pins. No dependency on a pre-populated local store, this worktree, or desk knowledge. |
| F-C2 | downstream record schema check | a claim record per D-06 | exit status | Rejects a claim carrying only an `ESTABLISHED` record, a missing or unnamed variant, a missing three-outcome field, and an Advance family with fewer than two distinctly purposed E records. |
| F-C3 | bundle assembler | the declared inventory per D-07 | the assembled bundle | Enumerates from the declared inventory. A tree walk may supply candidate entries but may not be the authority for what the bundle contains. |
| F-C4 | bundle completeness check | the declared inventory; an assembled bundle | exit status | Exits non-zero on a missing required entry or a mode mismatch. Has no warning level. Must have been shown to fail on a deliberately omitted entry before a clean assembly is accepted. |

## Unchanged surfaces

The existing extraction script, production-source contract, pin audit, S2
evidence executable and S2 contract keep their current signatures. Slice A adds
stages to the runner; it does not re-sign existing ones.
