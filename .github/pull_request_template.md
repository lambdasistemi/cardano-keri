<!--
Written for someone who wants to use or review this software and has only
this repository. Every claim must be checkable by that reader.
-->

## What changed

<!-- The behaviour that is different now, in the vocabulary of someone who
     uses this software. One paragraph. -->

## Why

<!-- The problem it solves; link the issue. For a defect, what a user or
     operator would have experienced. -->

## How to verify

<!-- Commands runnable from a clean checkout of this repository, or a link to
     the CI run. Nothing untracked, nothing machine-local. -->

## Lean correspondence and constitution

<!-- Read .specify/memory/constitution.md. For each changed behavior, identify:
     - the user story, the exact Lean commit and the definitions it implements;
     - the implementation entry points and the mapping of states, transitions,
       guards, accepted and refused outcomes, value flows, token identity and
       required evidence (signatures, receipts, proofs);
     - the checks and observed evidence at each claimed boundary, including
       negative controls, and real connected transitions for lifecycle claims.
     A fixture seeded in the final state does not prove the preceding journey.
     A gap the model deliberately leaves to the technical layer is named with
     the page that declares it. For a governance-only or docs-only change,
     explain why runtime behavior is unchanged.

     List model errors, ambiguities, missing semantics or conflicting upstream
     or consumer requirements as user-story escalations with the decision
     needed and the evidence, and add them to the Lean correspondence register.
     Affected acceptance stays blocked until the operator rules and the Lean is
     aligned first. Prior merges and expected gaps are not exceptions. -->

- [ ] The change follows the repository constitution; the model binding and
      evidence, or the reason runtime behavior is unchanged, are recorded above.
- [ ] No unresolved model error, ambiguity, contradiction or missing required
      evidence is being accepted as a passing affected behavior.

## Limits

<!-- What this deliberately does not do, and anything left unfixed. Say it
     plainly; a description that hides a gap costs the reader their trust in
     every other description. -->
