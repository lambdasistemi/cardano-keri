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
- Git extent discovery must propagate producer failures and reconcile changed
  names with numstat records one-to-one.
- The frozen command runner is rechecked immediately before every invocation.
- The dependency identity check covers the package workspace consumed by the
  builds, rather than a separate clean checkout.
- The existing traceability inventory captures and checks every theorem-name
  producer before consuming its output; its module list and trust policy stay
  unchanged.
- One exact frozen patch is the whole permitted traceability-script delta.
- One complete gate uses at most one expensive charged command so the owner,
  independent audit, and final verification all fit the shared ceiling.
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
5. Instrument layer: controls reject truncated Git outputs, binary or
   conflicting README input, a dirty consumed dependency, a wrong binding
   proposition, a custom axiom, one failed traceability producer, and runner
   drift at a later command boundary.

## Ordered slice

- **S-446-BIND:** Complete R-446-PIN through R-446-DOCS in one local owner
  candidate, one independent audit campaign, and one final commit.

## Verification limits

Passing establishes dependency provenance, compilation, and the exercised
transition inputs. It does not establish equivalence between Cardano KERI and
Singular models or migrate any Cardano KERI theorem.

## Ceiling

This file is limited to 3 KiB and 80 lines.
