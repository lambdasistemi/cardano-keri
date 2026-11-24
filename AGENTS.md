# Contributor instructions

Read [.specify/memory/constitution.md](.specify/memory/constitution.md) before
planning, implementing, reviewing or accepting work in this repository.

The accepted Lean model under `lean/` is the behavioral authority for every
layer that carries behavior: simulators, Aiken validators, Haskell builders
and the `ckeri` command line, generated vectors, the offered-API reference and
the docs. Repair code that contradicts clear Lean. If the Lean is wrong,
ambiguous, underspecified for a claimed behavior, or conflicts with a bound
upstream or consumer model, hold the affected acceptance and escalate to the
operator as a concrete user story with evidence; the Lean is rewritten first
and code is touched last. Do not invent a ruling, weaken an expectation or
count an unmet requirement as a pass. A gap the model deliberately leaves to
the technical layer is declared in writing before anything relies on it. All
of this applies to previously merged and released work.

Roles meet only on the chain (principle XII): no step performed by one role
may depend on anything another role hands over off chain, and there are no
layer-two mechanics. Everything the application validates about a request is
validated when the controller books, by the application mint. The folder is a
role of the Singular registry and is completely ignorant of this application;
`ckeri` wraps Singular's fold with an application adapter and holds no fold
logic of its own. A premise the model leaves opaque names the transaction and
the role that discharge it.

Stay consistent with the Singular command line and build on its code
(principle XIII): the same wallet, ledger-provider interface, fold, and rules
for time and settlement. What Singular lacks is built in Singular.

Open escalations are kept in the
[Lean correspondence register](https://github.com/lambdasistemi/cardano-keri/issues/435).

Every implementation, reuse, repair or acceptance governed by the Lean loads
the shared `code-the-design` skill: the Lean owns semantics and vocabulary,
every theorem has a bound Given/When/Then story, and every invariant has at
least two executable implementation test layers.

Use [.github/pull_request_template.md](.github/pull_request_template.md) to
record the story, the exact model revision, the implementation mapping and the
verification limits. The constitution defines the full rules and the amendment
process.
