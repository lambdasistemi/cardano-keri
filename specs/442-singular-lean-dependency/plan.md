# Plan: Singular Lean dependency binding

## Strategy

Deliver one bisect-safe dependency-binding slice. Add the released dependency,
make the default Cardano KERI library elaborate an executable binding check,
prove that check distinguishes a different well-typed action, build both Lean
libraries, and document the boundary.

## Constraints

- The accepted Cardano KERI Lean model and statements remain unchanged.
- Singular is consumed at its released `v0.6.1` identity.
- The executable check reaches the upstream transition, not a copied model or
  source-text proxy.
- The negative control must distinguish semantic mismatch from setup failure.
- No model migration starts in this ticket.

## Verification boundaries

1. Dependency layer: declared Git tag and resolved revision agree with the
   release identity.
2. Library layer: a committed check elaborates and evaluates the upstream
   transition during the default target build.
3. Consumer layer: an independent probe imports the Cardano KERI root and
   observes the same dependency boundary; its deliberate action fault fails.
4. Compatibility layer: both Cardano KERI libraries build and the repository
   Lean CI job passes on the exact PR head.

## Ordered slice

- **S-442-BIND:** Complete R-442-PIN through R-442-DOCS in one local owner
  candidate, one independent audit campaign, and one final commit.

## Verification limits

Passing establishes dependency provenance, compilation, and the exercised
transition inputs. It does not establish equivalence between Cardano KERI and
Singular models or migrate any Cardano KERI theorem.

## Ceiling

This file is limited to 3 KiB and 80 lines.
