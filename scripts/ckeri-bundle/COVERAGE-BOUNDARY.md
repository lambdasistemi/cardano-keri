# The shipped coverage boundary for #246 Slice B

Derived from this branch's own census and probes. Not from `A-e190-019`'s
withdrawn wording, and not manufactured to match a ruling. Every number below
carries the instrument that read it and the window it was read over.

## Prose form — for the `ckeri` evidence bundle

> **Coverage boundary — measured on this branch, not asserted.**
>
> The identity check enumerates the manifest's complete **parsed document**:
> `fields=372 reconciled=372 unexpected=0`, `containers=55
> uncovered_containers=0`, `enumerated_by=jq-leaf-and-container-paths` — the
> manifest's own top-level object included. Independently censused at 513
> mutants whose targets are enumerated from the artifact at run time:
> **500 killed, 1 survived, 12 inapplicable.** Every top-level addition, and a
> top-level `variant` contradiction, is rejected by name.
>
> Two boundaries remain, and both are measured rather than assumed.
>
> **1. The declared claim is narrower than the implemented coverage.** By
> operator decision of 2026-08-12 the declared invariant is scoped to
> `paths(scalars)` of `.identity` and `.records`, and
> `INV-246-IDENTITY-FIELD-EXPECTATION-DISJOINT` terminates `BLOCKED` on that
> scope decision. Top-level closure is *verified but not declared* — no reader
> may rely on it as a guarantee, whatever the implementation does. Restoring the
> wider claim is `T246-F7` and needs a scope change above this ticket.
>
> **2. The subject is the parsed document, not the published bytes.** The single
> census survivor is a UTF-8 BOM prefix (`bytes_differ=true
> document_identical=true`). A hand-crafted manifest whose bytes carry two
> `.identity.variant` keys also passes at `rc 0`: `jq` is last-wins and reads
> `defaultFunSemanticsVariantE`, while a conforming first-wins parser reads
> `defaultFunSemanticsVariantA`. The check further runs at build time inside the
> derivation and never at consumption, so nothing binds *these bytes* to *this
> verdict*. Tracked as `INV-246-PUBLISHED-ARTIFACT-CLOSURE` and
> `INV-246-ARTIFACT-CHECK-BINDING`, both `BLOCKING`, both assigned to the
> evidence-bundle slice.
>
> No exhaustive-mutation claim is made and equivalent mutants are not asserted
> absent. The campaign closed at set-point: every declared row terminal.

## Compact form — for the record that carries each verdict

```
coverage=parsed-document
  declared=.identity+.records   implemented=whole-document-incl-root
  census=500killed/1survived/12inapplicable
  residual=published-bytes-not-closed
  followups=T246-F7,INV-246-PUBLISHED-ARTIFACT-CLOSURE,INV-246-ARTIFACT-CHECK-BINDING
```

This is what must travel **in the same record as every verdict**, so a green
never travels without it.

## Provenance of every figure

| figure | instrument | window |
|---|---|---|
| `fields=372 reconciled=372 unexpected=0 containers=55 uncovered_containers=0` | shipped checker's own published record | clean source-built manifest at `9a45919e` |
| `500 killed / 1 survived / 12 inapplicable` | `auditor-B2-s2` `closure-census.sh` `28b4ce75…` | `census-candidate-9a45919.log` `ce1f77d0…` |
| top-level mutants `rc=0 SURVIVED` → `rc=1 KILLED` | same instrument, A/B across checkers | `census-base-6de4134d.log` `1460032b…` vs the above |
| `identity_variant_keys_in_bytes=2 last_wins=E first_wins=A checker_rc=0` | `published-bytes-vs-parsed-document.sh` `6e7137cf…` | `published-bytes-probe.log` `dde35ea8…` |
| BOM survivor `bytes_differ=true document_identical=true` | same probe | same log |

Both instruments were pre-flighted TDD-style against a known-defective seed and
shown to fail first: `PREFLIGHT-CONTROL single-key-preConway rc=1 outcome=REFUTED
(harness shown able to fail)`.

## Where it ships, and what remains owed

- **Reported upward now**, before any completion claim, as `A-e190-020` requires.
- The `ckeri` evidence bundle does not exist yet — it is Slice C's deliverable.
  The prose form is therefore **bound into Slice C's mandate** as a requirement on
  the bundle, and the compact form as a requirement on the records.
- Neither requires a build. `option_c_spend=0`.
