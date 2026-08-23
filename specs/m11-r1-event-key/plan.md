# Plan — R1 event-derived MPF key

## Bound state

- Sole ancestry base: `84e3b7159115e9169b57a85cbf9053b94aa889ba`.
- Issue lane: `ms11/r1-event-key-v2` in
  `/code/cardano-keri-ms11-r1-event-key-v2`.
- Re-cut continuation head:
  `8aa1de397d044ec40b62ecf16adf51eaa0795288`; published history is
  forward-only and PR #305 remains draft.
- Re-cut authority: `MANDATE-R1-RECUT-001.md`, SHA-256
  `d8eab8949b0ef3a5d0a32f78f4566f6109b7157d7e9866f93d94d7c34fe5fc20`.
- Semantic audit scope: the complete
  `84e3b7159115e9169b57a85cbf9053b94aa889ba..candidate` delta. Previous
  unaudited GREEN is inherited context, not acceptance evidence.
- Rejected submission-1 candidate:
  `224177c969fd7847d2519faa9d1dfaf6803ffa3b`; it remains immutable audit
  evidence and is superseded, never amended away.
- Accepted expansion authority: A-007, SHA-256
  `64281acaea5b33b48eabcdb1622f32cd2085d5a74828e63ff02c71e7e42e920e`.
- Post-change gate evidence culminates in inherited immutable v6 at
  `/tmp/ms-keri-11/r1-v2/gate/r1-event-key-v6.sh`; the re-cut adds only a
  lifecycle-falsified wrapper and does not re-derive v2--v6.

## Strategy

One bisect-safe OWNER slice audits and, where required, repairs the stable
event-key boundary, adapts
verified decoder output into that boundary, removes redeemer authority, and
updates the existing S0 reachability proof surface. Its single authorized
audit repair closes any full-delta finding without reopening A-019 semantics.
The inherited candidate already applies the repository's deployment-fixed
policy pattern, corrects the staging `i`/`d` boundary, and makes vector
coverage manifest-derived; none is credited until independently audited. The
event-key module owns
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
2. Lifecycle preflight first: normal cleanup, body-failure cleanup, and a
   seeded teardown failure must be distinguishable before any semantic
   instrument can judge the candidate.
3. Focused executable RED, then focused GREEN, with permanent mutation kills.
   R1-I14 separately requires two staging calls, two validator appends, two
   independent retrievals, and genuinely rival dressed sources. A name/count
   scan is only a lead; compiled execution supplies evidence.
4. Aiken formatting/check and packaged build surfaces when capacity grants
   each named leg.
5. Exact development-shell CI and repository CI only when authorized.
6. Fresh independent full-delta audit of the exact committed candidate.

No `--full`, Nix realization, Aiken realization, or CI run is authorized by
this plan. Authorization must arrive separately and is consumed per named
leg. The worker must stop cleanly at the first unauthorized boundary while
preserving an implementation handoff.

## Slice

**R1-S01-RECUT — derive and bind the authenticated event key.** Tasks
T001–T016. OWNER topology: Codex ticket owner → Grok 4.6 commit owner → fresh
Codex auditor in distinct acknowledged tmux panes. Draft tool is `NONE`;
maximum two audited submissions. The commit owner may commit locally but may
not push. The campaign carries one spent build against budget 2 and must not
start a realizing leg without the programme token followed by the host token.

F1--F3 and T011–T014 are inherited unresolved work, not closed findings. A
first re-cut audit may authorize one owner repair and a fresh submission-2
auditor. There is no third submission. Product writes start only after the
re-cut gate is frozen and falsified. All realizing legs obey the re-cut
resume threshold `56,000,000,000`, floor `53,687,091,200`, N=1 serialization,
token order, and per-leg byte journaling.

## Completion boundary

R1-S01 is accepted only after the fresh audit, ticket-owner task stamp, exact
tree proof, authorized final gate receipt, and CI. Until then the PR remains a
draft and R2 does not start.
