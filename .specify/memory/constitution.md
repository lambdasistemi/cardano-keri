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

**Version**: 1.0.0 | **Ratified**: 2026-07-07 | **Last Amended**: 2026-07-07
