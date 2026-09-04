# #363 — Checkpoint constructor inversions

Parent: #367

Artifact ceiling: 7,000 bytes and 150 lines.

## Outcome

An auditor can select any compiled `Checkpoint.Step` constructor and use one
public theorem to read its exact action, source state, guards, flow, and
successor. The compiled constructor inventory, not a handwritten count, is the
coverage denominator.

## Requirements

- **R363-01 — Exact inverse.** Each live `Step` constructor has exactly one
  public constructor-`iff` theorem. Its left side fixes the constructor's exact
  action, slot, source, flow, and successor; its right side names every proof
  premise in constructor order, exactly once. A guard-free constructor uses
  `True`, not an invented premise.
- **R363-02 — Derived denominator.** The coverage check obtains the non-empty
  constructor set from the compiled `Step` inductive and reports the tested
  numerator, denominator, constructor names, and inversion names. Intake at
  `main@9b2e6b8` derives 13 constructors; that observation is not a pinned
  acceptance count.
- **R363-03 — Public compiled surface.** Only declarations available after
  importing `CardanoKeri` count. A matching theorem in an unimported file does
  not satisfy coverage.
- **R363-04 — Structural binding.** Coverage rejects a missing inversion, two
  inversions for one constructor, an inversion registered for the wrong
  constructor, and an inversion whose type drops, duplicates, substitutes, or
  reorders a constructor guard or changes an indexed effect.
- **R363-05 — Self-falsification.** Fresh, compile-valid mutations for new
  constructor, missing, duplicate, wrong-constructor, dropped-guard, and
  outside-surface classes each make the exact frozen gate RED for the intended
  reason, with real exit codes and restored GREEN.
- **R363-06 — Proof trust.** All new theorems build with no `sorry`/`admit` and
  theorem-qualified `#print axioms` reports no axiom beyond `propext` and
  `Quot.sound`.
- **R363-07 — Additive only.** Existing theorem types and the production
  `Step`/`stepFn` definitions are byte-identical to the planning base.

## Invariants

- **INV-363-DENOMINATOR (BLOCKING):** every compiled constructor is covered
  exactly once and the denominator cannot be empty or silently shortened.
- **INV-363-EXACT-PREMISES (BLOCKING):** each inversion exposes all and only
  the constructor guards, in the constructor's binding.
- **INV-363-EXACT-EFFECTS (BLOCKING):** action, source, flow, and successor are
  the constructor's exact indexed result, including payment destinations and
  values.
- **INV-363-BINDING (BLOCKING):** each public inversion is bound to its named
  constructor; name/count agreement cannot satisfy a wrong binding.
- **INV-363-SURFACE (BLOCKING):** only the `CardanoKeri` imported surface can
  close a row.
- **INV-363-CAN-FAIL (BLOCKING):** each declared checker failure class has a
  witnessed RED and the unmutated candidate has a witnessed GREEN.
- **INV-363-TRUST (BLOCKING):** no escape proof or unapproved axiom enters a
  new inversion.
- **INV-363-IMMUTABLE (BLOCKING):** ratified theorem statements and production
  transition definitions do not change.
- **INV-363-SCOPE (BLOCKING):** implementation changes remain additive within
  the two owned Lean files; Registry, Lifecycle, Cage, Samaritan, simulator,
  on-chain, toolchain, and import-root files do not change.

## Rejection and limits

Any uncovered, duplicate, misbound, weakened, off-surface, untrusted, or
out-of-scope row rejects the candidate. The result proves exhaustive inversion
coverage over the current model vocabulary; it does not prove that vocabulary
matches product intent or exhaust arbitrary higher-order mutations.

