# Plan — R1 event-derived MPF key

## Bound state

- Sole ancestry base: `84e3b7159115e9169b57a85cbf9053b94aa889ba`.
- Issue lane: `ms11/r1-event-key-v2` in
  `/code/cardano-keri-ms11-r1-event-key-v2`.
- Frozen gate: `/tmp/ms-keri-11/r1-v2/gate/r1-event-key-v2.sh`, SHA-256
  `e22c0811fed611ad7aa1eeca07de71299b4dccaf370b9375e65768135177ecd1`.
- Gate freeze manifest: SHA-256
  `442f2b6bc57846561ba3d1917a54c8b531bfb70f6084ebaee69e2233a6711686`.

## Strategy

One bisect-safe OWNER slice introduces the stable event-key boundary, adapts
verified decoder output into that boundary, removes redeemer authority, and
updates the existing S0 reachability proof surface. The event-key module owns
canonical derivation; record insertion consumes its result. Existing decoder,
MPF, proof-token, and record-state responsibilities do not move.

The complete executable RED bundle precedes production changes. It covers all
R1 invariants and separately demonstrates assertion-level failure for the
frozen semantic mutation classes. The final candidate keeps those proofs as
permanent checks and supplies the gate-owned reproducibility artifacts.

## Boundaries

- Production: only the six onchain paths named by the frozen gate.
- Proof: event-key vectors and the existing S0 skeleton proof file.
- Reproducibility: `scripts/r1/mandate-bundle-v2.sh` and additional files below
  `specs/m11-r1-event-key/` that the gate requires.
- Planning: the six files in this directory are ticket-owner-owned and
  read-only to implementation workers.
- Forbidden: dependency/flake/CI edits, decoder edits, R2–R4 semantics, gate
  edits, pushes, and PR metadata changes.

## Verification stages

1. Free static readiness and exact candidate identity receipt.
2. Focused executable RED, then focused GREEN, with permanent mutation kills.
3. Aiken formatting/check and packaged build surfaces when capacity grants
   each named leg.
4. Exact development-shell CI and repository CI only when authorized.
5. Fresh independent audit of the exact committed candidate.

No `--full`, Nix realization, Aiken realization, or CI run is authorized by
this plan. Authorization must arrive separately and is consumed per named
leg. The worker must stop cleanly at the first unauthorized boundary while
preserving an implementation handoff.

## Slice

**R1-S01 — derive and bind the authenticated event key.** Tasks T001–T010.
OWNER topology: Codex ticket owner → Grok 4.6 commit owner → fresh Codex
auditor. Draft tool is `NONE`; maximum two audited submissions. The commit
owner may commit locally but may not push.

## Completion boundary

R1-S01 is accepted only after the fresh audit, ticket-owner task stamp, exact
tree proof, authorized final gate receipt, and CI. Until then the PR remains a
draft and R2 does not start.
