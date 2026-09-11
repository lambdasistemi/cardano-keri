<!--
Sync impact report
Version: 1.1.0 -> 2.0.0
Amended: 2026-09-11
Authority: the operator's instruction of 2026-09-11 that implementation must
never diverge from the accepted Lean, that a model error is escalated as user
stories and the Lean rewritten before code is touched, and that the rule
applies to previously merged work. Mirrors the Singular constitution 1.0.0
(lambdasistemi/singular, merged 2026-09-11), adapted to this repository.
Added principles: VII Lean is the behavioral authority; VIII model errors and
ambiguity require user stories; IX verify the whole claimed behavior;
X acceptance preserves evidence and gaps; XI apply the rule to previous work.
Amended: principle VI gains the precedence note (where a corollary and the
accepted Lean disagree, the Lean governs and the disagreement is escalated),
and its "no tombstones, ever" corollary becomes "tombstones are allowed under
conformance" by the operator's ruling of 2026-09-11 on register entry 1;
Development Workflow corrects "linear history via rebase merge" to merge
commits, which is the standing rule; Governance names the register.
Synchronized: AGENTS.md (new), CLAUDE.md (link), .github/pull_request_template.md
(new section), docs/index.md (start-here bullet).
Spec Kit templates: plan-template.md gates already defer to this file; no
migration required.
Open escalations at amendment time: issue #435, the Lean correspondence register.
-->

# cardano-keri Constitution

## Core Principles

### I. Design Before Implementation
Every feature starts in the design loop (`discussion.md`, `docs/`): the
on-chain model, trust assumptions, and invariants are written down and
vetted before any validator or library code lands. Adversarial
cross-model analyses (`vetting/`, `claude/`, `codex/`) are part of the
design record: superseded analyses are annotated, never deleted.
Per-issue specifications live in `specs/`.

### II. On-Chain / Off-Chain Parity
Every on-chain rule (Aiken) has an off-chain counterpart (Haskell) and
vice versa. Cross-layer test vectors are generated, never hand-written:
`offchain/` `gen-vectors` is the single source, and the Aiken tests
consume its output verbatim. A change on one side of the boundary is
incomplete until the other side and the vectors are regenerated in the
same PR.

### III. Protocol Strings and Layouts Are Frozen
Domain-separation strings (e.g. `"cardano-keri/value-write/v1"`),
message layouts, and serialization choices (canonical CBOR,
blake2b_256, Ed25519) are protocol surface. They change only by
introducing a new versioned identifier alongside regenerated vectors —
never silently, even pre-deployment.

### IV. Test-First
RED before GREEN: behavior changes start from a failing test. CI must
*execute* tests, not merely compile them — `aiken check` for on-chain,
the `unit-tests` suite for off-chain. A PR that weakens or skips a
failing test is rejected, not merged.

### V. Public-Repo Hygiene (NON-NEGOTIABLE)
No confidential third-party material and no negotiation notes may enter
the repository — tree, history, or PR refs. Meeting material lives
outside the repository (private archive). Anything intended for the
docs site must survive the question: "may an anonymous visitor read
this?"

### VI. The Chain Projects the KEL (NON-NEGOTIABLE)
**Precedence.** The corollaries below were written against the deployed V1
family on 2026-08-11. Where a corollary and the accepted Lean model disagree,
the Lean governs (principle VII) and the disagreement is an escalation under
principle VIII, never a silent edit of either. The first such escalation, the
convicted registry leaf against "no tombstones, ever", is entry 1 of the
[Lean correspondence register](https://github.com/lambdasistemi/cardano-keri/issues/435);
it was ruled on 2026-09-11 and produced the amended corollary below.

The chain projects the KEL; it never originates identity state. Every
identity-state fact written on chain must have a key-event preimage:
a signed KERI event whose exact bytes the transaction carries and the
validators check. A validator may reflect, gate, and refuse — it
may not pronounce. A proposed output asserting something about an
identity which no key event expresses is a wrong design, not an
unfinished one.

**Corollary — tombstones are allowed under conformance** (amended
2026-09-11; until then this corollary read "no tombstones, ever").
Terminality of conviction may be recorded as the registry's own lifecycle
state, a convicted leaf or a retired key, on one condition: the validator's
conviction predicate conforms to KERI's definition of duplicity as the
pinned specification states it (the Lean correspondence register, entry 3).
What is recorded is the projection's refusal to serve the identifier again,
not a verdict KERI would not pronounce, and the convict transaction in ledger
history remains the evidence. A terminal record written by a predicate that
does not conform is still a violation.

**Corollary — duplicate projections are not forgeries.** A second UTxO
projecting the same genuine, controller-signed event is a true
projection of an already-public fact. Whoever posts it pays the
deposit, cannot advance it (dual-threshold pre-rotation plus
spent-`TxOutRef` binding), and cannot close it: Close authorizes
against the datum's controller keys (`close.ak:89-95`), with
`refund_address` inside the signed preimage.
**The deposit is the anti-squat mechanism**, and a squatted checkpoint
stays redeemable by the AID's real controller.

**Corollary — consumers disambiguate by use, not by existence.** Where
two UTxOs project one AID, the resolution rule prefers the projection
the controller has actually advanced; a squatted duplicate is frozen
at seq 0 by construction. The KEL decides and the chain reflects, so
a consumer that resolves "the checkpoint for this AID" resolves it by
use rather than by counting candidates.

**Corollary — transaction context is NOT identity state.** Binding a
payee key hash, a refund address, or a spent `TxOutRef` originates
nothing about the identity: it names who this transaction pays and
which input it consumes. Such binding is always permitted and is
required where value leaves (`close.ak:31,63` does it correctly).
This principle must never be read as an argument against binding
context — unbound context is the #219 defect class, not compliance
with the projection law.

### VII. Lean Is the Behavioral Authority (NON-NEGOTIABLE)
The accepted, revision-bound Lean model under `lean/` MUST govern every
layer that carries behavior: the simulators, the Aiken validators, the
Haskell builders and the `ckeri` command line, the generated vectors and
conformance expectations, the offered-API reference and the docs. An
implementation MUST preserve the model's states, transitions, guards,
accepted and refused outcomes, value flows, token identity and the
evidence each transition requires. Imported code and pinned dependencies
carry the same obligation as code written here.

A passing suite, an existing implementation, an owner's interpretation, a
previous merge or a published release MUST NOT replace the model as the
authority. Contributors MUST NOT change the Lean, its corpus or an expected
result merely to match an implementation. The operator alone corrects the
model, through principle VIII.

**Declared technical gaps.** The model may deliberately not enter an area
because it is too technical, too complicated or too costly to formalize:
cryptographic primitives, serialization, transaction assembly, script
budgets, network discovery. Such a gap MUST be declared in writing, in the
model's documentation and on the affected design page, before any
implementation relies on it. An undeclared gap is a divergence. Whatever the
Lean does state MUST be true of the implementation.

### VIII. Model Errors and Ambiguity Require User Stories (NON-NEGOTIABLE)
If the Lean appears wrong, contradictory, underspecified for the behavior
being claimed, or ambiguous, or if it conflicts with a bound upstream or
consumer model, the contributor MUST stop and escalate to the operator. No
owner may choose one reading silently, weaken a requirement, or build the
other way first.

The escalation is a user story and MUST carry: the actor, action and intended
outcome ("As a ..., I want ..., so that ..."); a concrete starting state and
action, the Lean result or the competing readings, and the implementation's
observed result; the exact model and implementation revisions, definitions,
tickets and evidence, with the limits of that evidence; the user-visible
consequence, the viable alternatives, and the decision needed.

Acceptance, merge and release of the affected behavior and of every claim
that depends on it MUST stay blocked until the operator rules. Independent,
settled work continues. Repairing code that contradicts clear Lean needs no
ruling. A representation choice that preserves observable behavior, and is
checked to, is not a model error.

The ruling MUST be recorded in the repository with its story, in the
[Lean correspondence register](https://github.com/lambdasistemi/cardano-keri/issues/435)
or its successor. The Lean, its statements and proofs, its mutant ledgers and
its exported corpus MUST be updated first; the simulators, the implementation,
the vectors, the docs and release compatibility are then aligned to that
revision. Code is touched last.

### IX. Verify the Whole Claimed Behavior
Every behavior-changing pull request MUST identify its user stories, the
exact Lean revision and definitions it implements, the implementation entry
points, and the executable checks and observations that connect them. The
mapping MUST cover success and the relevant refusals, including who can
supply every signature, receipt and other required input. A representation
refinement MUST explain and check that observable effects are preserved;
matching case names or counts is insufficient.

A lifecycle claim MUST exercise the connected transitions that produce its
starting and final states. Seeding a fixture in the final state, substituting
an asset under another policy, or checking one validator in isolation MUST
NOT be presented as evidence for the missing journey; such a fixture supports
only the narrower check it actually performs, and says so.

Each form of evidence establishes only its own proposition: a source
inspection, a source fact; a Lean proof, its stated theorem; a simulator
replay, the simulated cases; a devnet or preprod claim, the corresponding
transaction and script execution. They MUST NOT be substituted for one
another, and a check MUST be shown to detect a reachable defect at the
boundary it claims.

### X. Acceptance Preserves Evidence and Gaps
Review MUST bind the candidate commit, the model revision, the commands, the
actual results and the remaining coverage gaps. Green CI is necessary for a
merge and does not by itself establish correspondence; the reviewer MUST
inspect what each gate proves, with its positive and negative controls.

An unresolved contradiction or ambiguity MUST NOT be closed as an expected
gap, waived by an owner, or converted into a passing row. Missing evidence
stays unverified. An unmet consumer requirement stays unmet even when the
implementation conforms to a different model. Changing the scope of an
accepted story requires an explicit ruling, and a release MUST NOT claim a
story whose required effects or evidence are missing.

### XI. Apply the Rule to Previous Work
Principles VII to X apply to code and artifacts merged or released before
this amendment. When a retrospective check finds a discrepancy, contributors
MUST record the affected revisions and stories in the register, preserve the
original evidence, and hold dependent acceptance until resolution. A prior
closure or a published release exempts nothing.

Repairs are forward changes. Historical commits, tags, artifacts and receipts
MUST NOT be rewritten to conceal a mismatch. Resolution is the implementation
repair with its evidence, or an explicit ruling followed by the model-first
alignment of principle VIII. Publishing this amendment resolves none of the
entries already in the register.

## Constraints

- On-chain: Aiken, Plutus v3; state anchored in MPFS tries
  (merkle-patricia-forestry).
- Off-chain: Haskell via haskell.nix (GHC 9.12 line), wasm-portable —
  no dependencies incompatible with a wasm32-wasi build of the core
  library.
- Identity model: KERI-style self-certifying AIDs with pre-rotation;
  bindings to CESR/vLEI follow the published CIPs and KERI specs, with
  deviations documented in `docs/design/`.

## Development Workflow

- Issue-backed PRs only; no direct pushes to `main`; merge commits (never
  rebase-merge, which recreates signed commits unsigned); Conventional
  Commits; one bisect-safe concern per commit.
- Every contributor and agent reads `AGENTS.md`, which points here, before
  planning, implementing, reviewing or accepting work. The pull request
  template's "Lean correspondence and constitution" section is the
  acceptance record: a behavior change supplies the story, model binding and
  checks; a governance-only change says why runtime behavior is unchanged.
- Nix-first CI on self-hosted `nixos` runners; the local gate mirrors
  CI and runs before every push.
- Docs are part of the deliverable: `mkdocs build --strict` and the
  link check gate every PR; the rendered site deploys from `main` to
  GitHub Pages.

## Governance

This constitution gates all spec/plan/tasks decisions: a plan that
violates a principle is reworked, not excepted. It records the operator's
instruction of 2026-09-11 and supersedes conflicting repository guidance and
prior owner interpretations; an agent or reviewer cannot grant itself an
exception, and only a later explicit ruling amends it. Amendments are made
by PR stating the authority, the rationale, the affected principles and the
dependent guidance, with the sync impact report updated: a major version for
an incompatible change of principle, a minor version for a new or materially
expanded principle, a patch for a clarification. Per-issue specs defer to
this document on conflict. The open escalations live in the
[Lean correspondence register](https://github.com/lambdasistemi/cardano-keri/issues/435).

**Version**: 2.0.0 | **Ratified**: 2026-07-07 | **Last Amended**: 2026-09-11
