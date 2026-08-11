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
The chain projects the KEL; it never originates identity state. Every
identity-state fact written on chain must have a key-event preimage:
a signed KERI event whose exact bytes the transaction carries and the
validators check. A validator may reflect, gate, and refuse — it
may not pronounce. A proposed output asserting something about an
identity which no key event expresses is a wrong design, not an
unfinished one.

**Corollary — no tombstones, ever.** Terminality of conviction means
the chain stops projecting: the AID token is burned and no
checkpoint-role successor is created, so the identity simply ceases to
resolve on Cardano. It does not mean the chain records a verdict about
the identity; KERI has no "this AID is dead" event for a validator to
project. Writing terminal identity state on chain is a
constitutional violation, not a feature request, and the convict
transaction in ledger history is the record.

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

- Issue-backed PRs only; no direct pushes to `main`; linear history via
  rebase merge; Conventional Commits; one bisect-safe concern per
  commit.
- Nix-first CI on self-hosted `nixos` runners; the local gate mirrors
  CI and runs before every push.
- Docs are part of the deliverable: `mkdocs build --strict` and the
  link check gate every PR; the rendered site deploys from `main` to
  GitHub Pages.

## Governance

This constitution gates all spec/plan/tasks decisions: a plan that
violates a principle is reworked, not excepted. Amendments are made by
PR that states the rationale and migrates affected artifacts.
Per-issue specs defer to this document on conflict.

**Version**: 1.1.0 | **Ratified**: 2026-07-07 | **Last Amended**: 2026-08-11
