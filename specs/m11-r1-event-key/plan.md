# Plan — R1 event-derived MPF key

## Bound state

- Sole ancestry base: `84e3b7159115e9169b57a85cbf9053b94aa889ba`.
- Issue lane: `ms11/r1-event-key-v2` in
  `/code/cardano-keri-ms11-r1-event-key-v2`.
- Rejected submission-1 candidate:
  `224177c969fd7847d2519faa9d1dfaf6803ffa3b`; it remains immutable audit
  evidence and is superseded, never amended away.
- Accepted expansion authority: A-007, SHA-256
  `64281acaea5b33b48eabcdb1622f32cd2085d5a74828e63ff02c71e7e42e920e`.
- Post-change gate: `/tmp/ms-keri-11/r1-v2/gate/r1-event-key-v4.sh`;
  its hash and freeze manifest are recorded at freeze time.

## Strategy

One bisect-safe OWNER slice introduces the stable event-key boundary, adapts
verified decoder output into that boundary, removes redeemer authority, and
updates the existing S0 reachability proof surface. Its single authorized
audit repair also applies the repository's existing deployment-fixed policy
pattern to append, corrects the opened staging `i`/`d` boundary, makes the
rival proof cross the complete production path, and makes vector coverage
manifest-derived. The event-key module owns
canonical derivation; record insertion consumes its result. Existing decoder,
MPF, proof-token, and record-state responsibilities do not move. The affected
append size row is re-measured after the parameterized program exists.

The complete executable RED bundle precedes production changes. It covers all
R1 invariants and separately demonstrates assertion-level failure for the
frozen semantic mutation classes. The final candidate keeps those proofs as
permanent checks and supplies the gate-owned reproducibility artifacts.

## Boundaries

- Production: the original six onchain paths plus `validators/s0_append.ak`,
  `m12/staging.ak`, and `validators/s0_staging_proof_token.ak`.
- Proof: event-key vectors and the existing S0 skeleton proof file, including
  a present-prior path witness and permanent finding-class properties.
- Reproducibility: `scripts/r1/mandate-bundle-v2.sh` and additional files below
  `specs/m11-r1-event-key/` that the gate requires, plus the affected append
  row in `specs/m11-s0-size-failfast/SIZE-REPORT.md`.
- Planning: the six files in this directory are ticket-owner-owned and
  read-only to implementation workers.
- Forbidden: dependency/flake/CI edits, decoder edits, R2–R4 semantics, gate
  edits, pushes, and PR metadata changes.

## Verification stages

1. Free static readiness, F1/F3 negative controls, and exact candidate identity
   receipt. The F2 boundary-name scan is placeholder-only and proves no
   execution.
2. Focused executable RED, then focused GREEN, with permanent mutation kills.
   R1-I14 remains unverified until the exact candidate runs v4 `--full`, whose
   mutation and Aiken-check legs are the binding F2 evidence.
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

The one A-007-authorized repair adds T011–T014 and is submission 2 of this
same campaign. Product writes start only after independent v4 verification.
All Aiken, Nix, mutation, size-measurement, packaged, cold, full, and CI legs
remain held under A-006 until the machine releases them.

## Completion boundary

R1-S01 is accepted only after the fresh audit, ticket-owner task stamp, exact
tree proof, authorized final gate receipt, and CI. Until then the PR remains a
draft and R2 does not start.
