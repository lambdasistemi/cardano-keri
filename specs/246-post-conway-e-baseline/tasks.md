# #246 tasks

Task IDs are stable. A slice is complete only when every task in it is checked
and the slice has been independently audited and accepted.

## Slice A — compatibility audit and its two controls

- [x] T246-A1 — Executable RED proof for INV-A1..INV-A9, failing for the
  intended missing behaviour rather than for setup, before any production
  change.
- [x] T246-A2 — Compatibility audit surface that resolves every reference the
  tracked bridge source makes into the three pinned upstream packages and
  reports resolved count and the complete unresolved set (INV-A1, INV-A2).
- [x] T246-A3 — Positive resolution control demonstrating in the same run that
  the resolver finds references that exist (INV-A2).
- [x] T246-A4 — Seeded retired-reference negative control that makes the audit
  report the seeded name unresolved and exit non-zero (INV-A3).
- [x] T246-A5 — Pin identity bound from the locked inputs rather than
  transcribed (INV-A4).
- [x] T246-A6 — Explicit reported answer on whether variant E and an era-based
  variant selection are expressible at the pins (INV-A5, D-04).
- [x] T246-A7 — Three-outcome records on every checked item, with
  `COULD-NOT-EVALUATE` naming its failed layer and forcing RED (INV-A6, D-01).
- [x] T246-A8 — Audit and both controls reached by the single flake-owned
  command the gate runs (INV-A7).
- [x] T246-A9 — `offchain/flake.lock` brought into sync so evaluation from a
  clean checkout leaves the working tree unmodified (INV-A8).
- [x] T246-A10 — Evidence that no bridge assertion, theorem, or existing check
  was weakened and no tracked Lean source was rewritten by the audit (INV-A9).
- [x] T246-A11 — The audit's own records name the commit they are about, so a
  source-compatibility result cannot be read against the wrong tree (R-09,
  INV-A10).
- [x] T246-A12 — Resolution decided by an oracle derived from Lean's own
  environment for the pinned packages, agreeing with the elaborator in both
  directions; a textual approximation does not satisfy it (INV-A1, F-A1).
- [x] T246-A13 — Reliance declaration filed before the RED bundle, in registry
  shape, with `enforced: NONE` available as a complete outcome.
- [x] T246-A14 — Every quantity the audit reports carries its instrument and
  its measurement window (R-12, D-09).

## Slice A2 — collector closure over the source language

Authorized re-cut inside #246 (A-001). Carries `INV-A1.v1` intact.

- [x] T246-A2-1 — Collector closure over the tracked source language, including
  syntax whose source spelling omits an upstream namespace; closure decided by
  the pins, not by the collector's own token pattern (`INV-A1.v1`).
- [x] T246-A2-2 — Every explicit cross-package reference is collected or the run
  reports `COULD-NOT-EVALUATE`/RED. No silent omission, no third outcome.
- [x] T246-A2-3 — Named killing mutant seeding an unrecognised or
  previously-omitted construct **of a class the collector does not already
  name** into tracked scope, making the real run RED rather than smaller.
- [x] T246-A2-4 — Honest bounded publication for `INV-A1.v2`: `collected`,
  `total`, coverage classes, collecting instrument, measurement window —
  remeasured against the candidate, never transcribed, and never a bare
  `unresolved=0`.
- [x] T246-A2-5 — The agreement record either states `agreement=by-construction`
  with its predicate named, or uses a genuinely discriminating second predicate.
  No non-falsifiable assertion ships labelled as a measurement.
- [x] T246-A2-6 — `INV-246-RESOLUTION-CLOSURE-BINDING` killed: the audit record
  names the store path the oracle resolved against, and it is the tracked
  package's own build root.
- [x] T246-A2-7 — `INV-246-PINNED-MODULE-GRAPH` killed by a named mutant, not
  only structurally verified.

## Carried follow-ups

Filed inside #246 with named owners. These exist so an `ADVISORY` row can
terminate `RESIDUAL` against a real ID rather than an invented one; no new
ticket is authorized.

- [x] T246-F1 — Seed an actual `offchain/flake.lock` rewrite and require the run
  RED. Owner: the Slice A2 commit owner. *Closed by Slice A2:
  `actual-lock-rewrite` performs a real `jq` rewrite of a lock copy and asserts
  the digest moves, with both locks bracketed by live before/after digests.
  **Remaining honest limit:** lock stability is proven for this runner over this
  invocation window, not for arbitrary evaluation of the flake.*
- [ ] T246-F2 — Publish the discriminating input the run already computes: emit
  an `AUDIT-DISAGREEMENT` record for the input on which the elaborator and
  declaration-membership predicates differ, so the published record **exhibits**
  one rather than merely the run containing one. Owner: a later #246 slice.
  Follow-up for `INV-246-COMPARISON-DISCRIMINATION` (`RESIDUAL`). **Honest limit
  of what ships without it:** the green establishes that a discriminating input
  exists inside the run, not that the record shows it — which is what the row
  asks. Zero `AUDIT-DISAGREEMENT` lines are emitted today.
- [ ] T246-F3 — Share one package-attribution predicate across every instrument
  that maps a module or reference to a pinned package; `collect-lean-references.pl`
  calls the same lookup rather than re-implementing a prefix list with no
  `Cryptograph` arm. Owner: a later #246 slice. Follow-up for
  `INV-246-PACKAGE-ATTRIBUTION-AGREEMENT` (`RESIDUAL`). **Honest limit of what
  ships without it:** the green establishes that the tracked numerator and
  denominator share one predicate, not that every attributing instrument does.
  The direction of harm stays closed only because the perl population feeds no
  denominator, and nothing enforces that.

## Slice B — frozen post-#219 / post-Conway baseline identity

Dispatched after Slice A is accepted; its invariants are versioned before
dispatch.

- [ ] T246-B1 — Baseline blueprint reproducible from source at the anchor
  commit with the Aiken version the repository validates with (F-B1).
- [ ] T246-B2 — Mechanical evidence of what a cold store does with the previous
  baseline artifact, as a check that runs inside the gate (F-02).
- [ ] T246-B3 — Manifest over all 23 titles and 8 distinct programs with every
  field computed (F-B2, D-05).
- [ ] T246-B4 — Variant E bound as the evaluation identity, with any
  version-derived selection named separately (F-B3, D-04).
- [ ] T246-B5 — Mutation of any single manifest input makes verification exit
  non-zero and name which input moved.
- [ ] T246-B6 — Historical C / pre-#219 material relabelled in place, neither
  deleted nor reinterpreted.
- [ ] T246-B7 — Identity-consistency check that goes RED when any element of
  the triple is unnamed or when the elements describe different configurations,
  applied to every record including verification receipts (R-09, D-08).
- [ ] T246-B8 — That check demonstrated RED against the retained pre-slice
  receipt before any clean baseline is accepted; the retained receipt is not
  repaired, rewritten, or deleted (R-10).

## Slice C — stranger-runnable bundle skeleton and downstream record schema

Dispatched after Slice B is accepted; its invariants are versioned before
dispatch.

- [ ] T246-C1 — Bundle entry point depending on nothing outside a fresh
  checkout and its declared pins (F-C1).
- [ ] T246-C2 — Reproduction exercised against a genuinely fresh clone rather
  than the issue worktree (R-05).
- [ ] T246-C3 — Downstream claim schema enforcing the per-claim
  falsifier-before-GREEN pair (D-06, F-C2).
- [ ] T246-C4 — Advance family required to carry two distinctly purposed E
  records, each stating its own purpose (D-06).
- [ ] T246-C5 — Schema check reachable from the same runner the gate executes.
- [ ] T246-C6 — Declared bundle inventory; tree enumeration may contribute
  entries but does not define coverage (R-05a, D-07, F-C3).
- [ ] T246-C7 — Completeness check that exits non-zero on a missing required
  entry or a mode mismatch, executable bit included (R-05b, F-C4).
- [ ] T246-C8 — Falsifier for the completeness check: one declared artifact
  deliberately omitted, shown RED before the clean assembly is shown GREEN
  (R-05c).
- [ ] T246-C9 — The assembled bundle executed from a location with no access to
  the issue worktree, as a run rather than a claim (R-05d).
- [ ] T246-C10 — Every completeness result publishes `declared` beside
  `missing`, and every other aggregate publishes its denominator (R-11, D-07).
- [ ] T246-C11 — An absent, unreadable or unexpectedly empty inventory yields
  `MEASUREMENT-FAILED`/CNE/RED rather than a zero (R-11, D-01).
- [ ] T246-C12 — **Both** branches falsified before the clean assembly is
  accepted: a deliberately omitted declared artifact goes RED (T246-C8) **and**
  an empty or unreadable inventory goes RED. Falsifying only the interesting
  branch is how the two states stay indistinguishable (R-05c, R-11).
