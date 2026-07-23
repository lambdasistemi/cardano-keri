# Tasks: close a checkpoint and resolve ACTIVE state (#117)

Each implementation slice is one driver/navigator RED→GREEN commit. Task boxes
are checked only after the ticket owner reviews the complete diff and actual
commit, reruns the required verification, amends the same commit, and pushes.
Q-013 must be ratified before any S1 dispatch.

## Planning checkpoint

- [X] T117-PLAN Freeze the reversed invariant in `spec.md`: burn one named
      ACTIVE checkpoint, never bar the AID, and allow later same-AID Register.
- [X] T117-PLAN Pin current-controller Close authorization, exact signed refund,
      ACTIVE-only dispatch, and no CLOSED role or O3/O4 rebuild.
- [X] T117-PLAN Pin the CIP-31 supplied-reference-only soundness boundary and
      prohibit global-unicity claims, MPF/shared state, or an ordering service.
- [X] T117-PLAN Produce four bisect-safe slices with owned files, exact commits,
      RED/GREEN evidence, parity gates, and the hard measurement stop.
- [X] T117-PLAN Run the cross-artifact planning audit, repair all findings, pass
      planning hygiene, and commit exactly
      `docs(117): specify checkpoint close and lookup` with exactly
      `Tasks: T117-PLAN`.

## Slice 1 — Close message and controller predicate

- [ ] T117-S1 RED freezes the ten-field constructor-0 Close message, domain,
      canonical-CBOR bytes, and full refund-address encoding in Haskell/Aiken.
- [ ] T117-S1 RED covers reconstruction and controller authorization at two-key
      and GLEIF seven-key shapes, including below-threshold, bad/out-of-range,
      duplicate-inflated, wrong-key, field-mutation, and fresh-outref replay
      negatives.
- [ ] T117-S1 GREEN adds the validator-free Haskell/Aiken Close model by reusing
      existing canonical-CBOR, Ed25519, distinct-index, and threshold logic.
- [ ] T117-S1 `CloseEvidence` carries only the full refund address and indexed
      current-controller signatures; every other message field is reconstructed
      from deployment, named outref, and OLD datum.
- [ ] T117-S1 Haskell-generated Aiken vectors run twice without drift; focused
      suites and `./gate.sh` pass; commit exactly
      `feat(117): define controller-authorized close` with exactly
      `Tasks: T117-S1`.

## Slice 2 — live ACTIVE Close burn and refund

- [ ] T117-S2 RED proves honest ACTIVE Close currently fails and adds C-N1–C-N14
      plus C-P1/C-P2 full-context transaction coverage before GREEN.
- [ ] T117-S2 Add `MintRedeemer.CloseBurn { checkpoint_ref }`; require that
      exact reference to identify one inline-V1 ACTIVE input with its derived
      quantity-one token, no sibling input carrying that policy/name, and an
      exact one-pair `-1` own-policy mint map.
- [ ] T117-S2 Admit `SpendRedeemer.Close { evidence }` only from classified
      ACTIVE; keep FROZEN, TOMBSTONE, unknown-role, and datum mismatch fail-closed.
- [ ] T117-S2 Run the S1 current-controller predicate, repeat the exact same
      burn check, forbid every output carrying the target policy/name, and
      require one dedicated signed non-checkpoint refund output equal to the
      complete input value minus the burned token.
- [ ] T117-S2 Preserve extra ordinary fee inputs/change and executable
      close-then-same-AID-Register; add no mint-once bar, role, MPF/shared state,
      or `d_reg` change.
- [ ] T117-S2 Focused full-context tests and `./gate.sh` pass; commit exactly
      `feat(117): close active checkpoints by burn` with exactly
      `Tasks: T117-S2`.

## Slice 3 — CIP-31 ACTIVE resolver and parity

- [ ] T117-S3 RED adds Haskell/Aiken L-P1–L-P3 and L-N1–L-N11 vectors plus
      Aiken tests over complete transactions' actual `reference_inputs`.
- [ ] T117-S3 Add the shared `ReferenceInputView` decision model and generated
      vectors without importing or inventing an off-chain UTxO discovery service.
- [ ] T117-S3 Add public
      `resolve_active_checkpoint(checkpoint_policy_id, cesr_aid, tx)`; derive the
      token name internally and inspect only `tx.reference_inputs`.
- [ ] T117-S3 Filter exact ACTIVE full address plus quantity-one trusted token
      before datum parsing; require exactly one supplied candidate, inline
      well-formed V1, matching AID/name, and return its actual outref+datum.
- [ ] T117-S3 Prove unrelated refs and ACTIVE+historical-TOMBSTONE succeed while
      inactive, closed/absent, wrong-policy/address/value/datum, and supplied
      same-token ambiguity return `None`.
- [ ] T117-S3 API comments and tests explicitly limit uniqueness to supplied
      reference inputs; no global scan, unicity claim, batcher, sequencer, or
      shared state appears.
- [ ] T117-S3 Haskell-generated Aiken vectors run twice without drift; focused
      suites and `./gate.sh` pass; commit exactly
      `feat(117): resolve active checkpoint references` with exactly
      `Tasks: T117-S3`.

## Slice 4 — measurements and hard acceptance gate

- [ ] T117-S4 RED adds the exact eight-row #117 measurement title gate and a
      report that fails on missing/placeholder results.
- [ ] T117-S4 Measure two-key and GLEIF seven-key Close spend and CloseBurn mint
      handlers, then mechanically sum raw memory/CPU for both complete Close
      transactions.
- [ ] T117-S4 Measure two-key and GLEIF seven-key resolver calls over complete
      transaction reference-input fixtures, not a prefiltered pure substitute.
- [ ] T117-S4 Record raw units, used percentages, and headroom in
      `MEASUREMENTS.md` at reference `d_reg = 1_000_000_000`; leave the #116
      exact-nine measurement set unchanged.
- [ ] T117-S4 Every required row retains at least 25.00% memory and CPU headroom
      (`mem <= 10,500,000`, `cpu <= 7,500,000,000`) or STOP before commit and
      raise the next epic Q-file; no reduced fixture or live-node overclaim.
- [ ] T117-S4 `just measure-close-lookup` and `./gate.sh` pass; commit exactly
      `test(117): measure close and reference lookup` with exactly
      `Tasks: T117-S4`.

## Orchestrator lifecycle after ratification

- [ ] Q-013 is answered and consumed before S1 driver/navigator dispatch.
- [ ] Each slice follows driver RED → navigator RED approval → driver GREEN →
      navigator GREEN approval → one exact commit; workers never push.
- [ ] Ticket owner reviews every changed file and commit, verifies forbidden
      scope is absent, reruns focused checks plus a fresh `./gate.sh`, checks
      only that slice's boxes, amends the same commit, and pushes with
      force-with-lease.
- [ ] PR #123 remains draft and `gate.sh` remains present until a separate
      epic-owner mark-ready acceptance. No ready, merge, or old-spec/docs action
      is authorized by this plan.
