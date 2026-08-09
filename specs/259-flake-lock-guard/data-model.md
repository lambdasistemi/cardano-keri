# Data model — #259 flake-lock enforcement

Artifact ceiling: 4,000 bytes and 110 lines.

## DAT-259-DECLARED-INPUT

A direct attribute name in the primary `offchain/flake.nix` input set. Nested
`inputs.*.follows` declarations are relationships of their owning direct
input, not additional root inputs.

## DAT-259-LOCKED-INPUT

A key in the committed `offchain/flake.lock` root input map. Its mapped node or
follow path must exist in the committed lock graph.

## DAT-259-INVOCATION

One executable Nix command that evaluates the primary offchain flake, with:

- source surface: root justfile or GitHub CI workflow;
- source location;
- effective working directory or explicit flake reference;
- Nix operation;
- presence of `--no-write-lock-file`.

Remote `nix shell` commands and commands rooted at auxiliary flakes are not
members of this population.

## DAT-259-GUARD-REPORT

A process result containing non-zero observed counts for direct declarations,
locked root inputs, classified justfile invocations, classified workflow
invocations, and durable callers. Failure identifies the violated invariant
class without editing repository state.

## Relationships and validation

- Every **DAT-259-DECLARED-INPUT** maps to one root
  **DAT-259-LOCKED-INPUT**.
- Every **DAT-259-INVOCATION** has the no-write flag.
- Both **MOD-259-JUST** and **MOD-259-WORKFLOW** call the shared guard.
- A zero observed population, malformed source, unknown in-scope Nix command,
  missing map target, or source read failure is invalid rather than success.

## State invariants

- **DATA-INV-259-01:** declared input names are a subset of committed root-lock
  input names and every mapped target resolves in the lock graph.
- **DATA-INV-259-02:** guard execution has no tracked or untracked repository
  write effect.
- **DATA-INV-259-03:** a successful report carries positive counts for both
  invocation surfaces and both caller edges.
