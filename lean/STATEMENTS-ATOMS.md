# Statement and semantic-atom ledgers — ACDC, TEL mirror, delegation (proved)

STATEMENTS mode, authored 2026-09-10 against `main@88e9309`. Authority:
`docs/design/credential-verification.md` (decision recorded 2026-09-10),
[#391](https://github.com/lambdasistemi/cardano-keri/issues/391),
[#392](https://github.com/lambdasistemi/cardano-keri/issues/392),
[#292](https://github.com/lambdasistemi/cardano-keri/issues/292), #31 as
amended by #391, `docs/acdc-primer.md`, `docs/design/defi-gate.md`, and the
KERI superseding rules A0/A1/A2/B1/B2/B3/C (feasibility report §4.2).

The rows below are **creator claims** for an independent statement audit
(`lean-auditor`), never self-certified coverage: each theorem names the
reachable witness of its antecedent and the single-atom mutant expected to
falsify it. Statement hashes are frozen only after that audit returns ready.

Build: `cd lean && lake build CardanoKeriStatements`. Surface: 71 statements,
all proved — `#print axioms` reports at most `propext`, `Quot.sound` and
`Classical.choice`, never `sorryAx` — and 39 executable probes in
`Statements/Probes.lean` that build only if every scenario holds. Proofs
live beside the statements; proof-side lemmas in `Statements/*Helpers.lean`.
The default target `lake build` does not include this library, so the
zero-`sorry` gate of `scripts/check-lean-traceability.sh` is unaffected.

## Repair log

- **Repair 1** (2026-09-10, statement audit, four findings): admission
  binds the actor to the leaf credential's issuee (C13, C14); rule-B
  superseding compares the approval's position and refuses an older
  approval (H9, H10, D11, D14); insert-only statements take a
  well-formedness or reachability premise (H8, D12); stored dependencies
  are tied to eviction after superseding (C14, C15).
- **Repair 2** (2026-09-10, proof work): M2, M4, M9 take a reachability
  premise — over arbitrary systems a registry stored under a key other than
  its id makes them false; reachable systems store every registry under its
  id (`MirrorHelpers.Ok`).
- **Repair 3** (2026-09-10, invariant review, six findings and four
  boundaries): see the dispositions below.
- **Repair 4** (2026-09-10, proof work): D4 takes collision resistance of
  the event digest as a hypothesis, as S6 does for the TEL digest; without
  it a certificate named by one event's digest installs another event with
  the same digest and the toad binding is refutable. All 71 statements are
  then proved.

### Dispositions of the invariant review (2026-09-10)

| Finding | Disposition | Where |
|---|---|---|
| 1. Cross-hop issuer authority | **Closed.** `Policy.links` pins one link per edge; `chainFrom` refuses a failing link. The vLEI link `issuerIsIssuee` is defined; the probe's unlinked chain is refused under it and admitted only under a lax link. | C1, C16; `Probes.C` |
| 2. Authorization after superseding, before eviction | **Open decision, stated residual.** The design authority specifies cache-then-evict; the gate reads no checkpoint (C12). The interval is bounded by the freshness bound and closed by permissionless eviction on evidence (C9, C15). Closing it at the use boundary would have the gate read the issuer checkpoint of every provisional dependency and run `Anchor.stands` — one reference input and two lookups per provisional dependency; final admissions unaffected. Not taken here. | C20 (witness); `Probes.C` finding 2 |
| 3. Outstanding and consumed provisional certificates | **Closed.** A certificate records its walk's anchor; a provisional certificate is consumed only while the anchor stands on the parent's checkpoint under the consumer's range proof; a stale one installs nothing. Already-installed children stand (D13, the #292 omission, unchanged). | D2, D15, D17; `Probes.D` finding 3 |
| 4. B3 and C/C1 recovery | **B3 closed; C/C1 excluded fail-closed.** `Approval` carries the parent event's kind; `before` orders B1, B2, B3 and refuses A2. C/C1 (precedence decided further up the chain) is not represented: such a rotation is refused. Consequence: a child whose recovery needs the grandparent's ordering cannot supersede on-chain until a later ruling models the climb. | H9, H10, D14, D18; `Probes.D` finding 4 |
| 5. Admission renewal | **Closed.** An admission is replaced only when expired; an expired admission is removable by anyone; a live one is never replaced. | C14, C18, C19; `Probes.C` finding 5 |
| 6. Registry inception validity | **Closed.** A registry records its inception anchor; every hop requires it to stand under the presenter's range proof; anyone may re-anchor the same `vcp` by a fresh walk on the issuer's accepted branch. Revocations pushed meanwhile stay (fail closed). | M7, M12, M13, C17; `Probes.O` |
| Event well-formedness | **Closed.** `TelEvent.wellFormed` (#392 sequences; a `vcp` names itself) is required by every walk. | S8; `Probes.C` |
| Exact installation provenance | **Closed.** D4 binds the leaf's toad to the event; D15 binds the consuming transition to the exact leaf, approval and certificate. D5's prose now claims outstanding-token absence only; D16 says a re-mint cannot re-install. | D4, D5, D15, D16; `Probes.D` |
| Lifecycle composition | **Explicit limit.** `leave` merges parked and convicted and permits re-registration; conviction terminality and revival from the parked key state are `Checkpoint`'s guarantees (T12, T8), not this model's. Revival is modelled as a fresh registration with its inception certificate. | module docstring; `Probes.D` revived |
| Bounded eviction work | **Closed.** `Anchor.moved` takes the evidence `m` (one lookup); `Anchor.stands` takes a range proof (two lookups). No scan of the history remains. | H12, C9 |

## Model surface

| Module | What it models | Executable core |
|---|---|---|
| `Statements/History.lean` | key-state history leaves with back-pointer; `advance` (insert), `supersede` (rule B update with B1/B2/B3 precedence); the range proof `cover`; the seal walk `walkOn` / `sealWalk` over well-formed TEL events; anchors with `stands` and `moved` | `hstep`, `cover`, `walkOn`, `sealWalk`, `Anchor.stands`, `Anchor.moved` |
| `Statements/Mirror.lean` | per-registry revoked set with its inception anchor; `open` from a sealed `vcp`; permissionless `push` of a sealed `rev`; `reanchor`; `miss` | `Mirror.stepFn`, `miss` |
| `Statements/Credential.lean` | ACDC chain admission (integrity, edges, policy links, schema, root pin, depth, `iss` walk, absence, registry anchor) bound to the actor; the cage with anchored dependencies; `evict` on evidence; `expire`; `gate` | `admitChain`, `Credential.stepFn`, `gate` |
| `Statements/Delegation.lean` | approval certificates with position and anchor, minted by the seal walk on the parent; consumed by `dip`/`drt` with re-validation of provisional anchors; rule-B superseding; `leave`; the ancestry walk | `Delegation.stepFn`, `ancestorWithin` |

Modelling assumptions, stated in the module docstrings: no cryptography
(epochs for key states, decidable `signed`/`receipted`, digests as functions
with injectivity hypothesised where needed); no MPF (a root is the map it
commits to; a proof is a lookup); no bonds, fees or attestation-token cuts
(#397); the actor's own threshold is `Checkpoint.consumableState`.

## Theorem ledger

Columns: theorem; the ruling or design sentence it answers to; a reachable
witness that makes the antecedent true; the single-atom mutant expected to
falsify it; kind (`G` guarantee, `I` public inversion, `W` witness of a
stated limit — an existential, not a guarantee); status (all `proved`).

### History and seal walk — `HistoryGoals.lean`

| Theorem | Ruling | Witness of antecedent | Falsifying mutant | Kind | Status |
|---|---|---|---|---|---|
| `H1_wf_reachable` | #391 "insert-only", leaf `prev_sn` | register, advance to 12, advance to 40 | `advance` with `prev := none` | G | proved |
| `H2_cover_sound` | #391 "no rotation sits between `e` and `k`" | leaves 0, 12, 40; `cover 12 17 (some 40)` | drop `k < e'` | G | proved |
| `H3_cover_complete` | #391 "or `e == native_sn`" | leaves 0, 12; `Governs 12 17` | refuse `succ = none` | G | proved |
| `H4_provisional_iff_latest` | rule A0, design "provisional" | leaf 12 latest, `cover 12 17 none` | `final` on `succ = none` | G | proved |
| `H5_final_is_stable` | design "its admission is final" | `cover 12 17 (some 40) = final`, then advance to 50 | `supersede` touching non-latest leaf | G | proved |
| `H6_superseding_excludes` | rule A0, design "superseding recovery" | `cover 12 17 none = provisional`, advance to 15 | `k ≤ e'` in `cover` | G | proved |
| `H7_provisional_becomes_final` | #391 step 2 | `cover 12 17 none = provisional`, advance to 40 | wrong back-pointer on advance | G | proved |
| `H8_non_delegated_insert_only` | rule A1 | well-formed non-delegated, any step | `supersede` without `parent` guard | G | proved |
| `H9_supersede_only_latest` | rules B1–B3, #391 "MPF `update` of the latest leaf" | delegated at latest 12 installed by (3, ixn, 0), `supersede 12` with (4, ixn, 0) | accept `sn' ≠ latest` | G | proved |
| `H10_older_approval_cannot_supersede` | rules B1–B3, A2 | leaf installed by (3, ixn, 0), certificate at (2, ixn, 0) | drop `a.before appr` | G | proved |
| `H11_final_anchor_stands` | design "its admission is final" | final anchor of leaf 12 with successor 40, then advance to 50 | `supersede` touching a non-latest leaf | G | proved |
| `H12_moved_refutes_stands` | design "evicts a provisional admission when …" | anchor (12, 17) provisional, leaf inserted at 15 | `moved` accepting a leaf above `k` | G | proved |
| `S1_walk_needs_leaf_signature_and_receipts` | #392 step 3, #391 "receipt gate" | walk with `signed`/`receipted` true at leaf 12 | drop `receipted` | G | proved |
| `S2_walk_binds_seal_at_index` | #391 "without every link", #392 step 1 | seal at index 0 of an `ixn` at 17 | compare `seal.i` only | G | proved |
| `S3_walk_ignores_current_keys` | design "never mixed" | any walk | check `env.signed c.cur` | G | proved |
| `S4_current_key_thief_only_provisional` | primer Q4 "killed by owner rotation" | env signing only at `cur`; walk on latest leaf | `final` on latest leaf | G | proved |
| `S5_walk_verdict_is_cover_verdict` | design verdict travels with the walk | any successful walk | constant verdict | G | proved |
| `S6_seal_names_one_event` | #391 "a credential it never sealed" | two walks, same `ixn`, same index | `sealOf` without digest | G | proved |
| `S7_establishment_seal_is_own_leaf` | #392 "for a `rot` the covering leaf is the event itself" | `rot` at 12 sealing a `vcp` | drop `w.e = w.kel.sn` | G | proved |
| `S8_walk_needs_well_formed_event` | #392 TEL sequences | a `vcp` at 0 naming itself | drop `wellFormed` from `sealWalk` | G | proved |

### Mirror — `MirrorGoals.lean`

| Theorem | Ruling | Witness of antecedent | Falsifying mutant | Kind | Status |
|---|---|---|---|---|---|
| `M1_only_the_issuer_revokes` | #392 "the issuer's own cryptography is the permission" | register, open, push one `rev` | `push` without `sealWalk` | G | proved |
| `M2_revocation_is_permanent` | design "over-revokes and fails closed" | reachable registry with one SAID, any step | a delete action | G | proved |
| `M3_duplicate_push_refused` | #392 "duplicate pushes fail on `insert`" | push the same `rev` twice | re-insert resets set | G | proved |
| `M4_pushes_commute` | #392 "converges however it is filled" | two `rev`s, distinct SAIDs, reachable | position-recording accumulator | G | proved |
| `M5_registry_bound_to_issuer` | #392 registry row: "registry id bound to issuer AID" | open from a `vcp` | trust the `issuer` argument | G | proved |
| `M6_push_iff` | #392 "no owner authorization, no current-key check" | as M1 | guard on `cur` | I | proved |
| `M7_open_iff` | #392 `vcp` row; inception anchor | as M5 | accept `iss` as inception | I | proved |
| `M8_mirror_ignores_current_keys` | #392 "current keys cannot vouch for past events" | open/push/reanchor after `setCur` | require `signed c.cur` | G | proved |
| `M9_superseded_push_over_revokes` | design "revocations pushed under them stay in the set" | provisional push, then advance at or below `k` | evict revocations on superseding | G | proved |
| `M10_freshness_unenforced` | #392 "absence in the mirror is not absence in the KEL" | constructed: sealed `rev`, never pushed | none (stated limit, #398) | W | proved |
| `M11_miss_fails_closed` | design "each against its own registry" | unopened registry | `true` on `none` | G | proved |
| `M12_reanchor_iff` | review finding 6 | registry opened at leaf 0, issuer at 1, same `vcp` sealed at 3 | `reanchor` resetting the set | I | proved |
| `M13_inception_is_a_walk_anchor` | review finding 6 | as M12 | `reanchor` storing a supplied anchor | G | proved |

### Credential — `CredentialGoals.lean`

| Theorem | Ruling | Witness of antecedent | Falsifying mutant | Kind | Status |
|---|---|---|---|---|---|
| `C1_admitted_chain_is_pinned` | primer Q4 pin 2, verifier bound 4 | 2-hop chain to the root | drop root check on last hop | G | proved |
| `C2_every_hop_sealed_by_its_issuer` | primer Q4 pin 3, #31 amended | as C1 | walk against presenter's checkpoint | G | proved |
| `C3_integrity_and_edges` | primer Q4 pin 1, "swap parent breaks edge SAIDs" | as C1 | ignore `edge` | G | proved |
| `C4_revoked_link_refuses` | primer pin 4 "cascade" | chain with parent SAID pushed | mirror check on leaf only | G | proved |
| `C5_unopened_registry_refuses` | design "one absence proof per link" | hop whose registry is unopened | missing registry = clean | G | proved |
| `C6_provisional_iff_some_hop` | design "provisional when e is the latest leaf" | one hop on its issuer's latest leaf | `meet` final on any final | G | proved |
| `C7_admission_ignores_current_keys` | design "never mixed" | any chain, `setCur` | `hopVerdict` checking `cur` | G | proved |
| `C8_final_never_evicted` | design "evicts a provisional admission" | final admission, any evidence | `moved` ignoring the verdict | G | proved |
| `C9_evict_iff` | design "inserts a leaf at or below that sequence number" | provisional admission, issuer advance ≤ `k`, evidence of that leaf | evict on a leaf above `k` | I | proved |
| `C10_cascade_at_gate` | design "a revoked QVI credential fails every chain below it" | admitted chain, push of a parent SAID | gate on leaf registry only | G | proved |
| `C11_gate_iff` | defi-gate "cheap lookup + freshness bound" | fresh admission, all links absent | drop freshness bound | I | proved |
| `C12_gate_reads_no_checkpoint` | design "with no signature checks" | any gate | re-walk a seal | G | proved |
| `C13_admission_binds_actor` | defi-gate: admission under the acting entity | leaf issued to 7, admitted under 7; refused under 999 | drop the issuee guard | G | proved |
| `C14_admit_iff` | design cage; renewal | as C13; expired key | cache empty dependencies | I | proved |
| `C15_provisional_admission_evictable_after_superseding` | design "evicts a provisional admission when …" | provisional hop on leaf 12 sealing at 17, issuer advances to 15, evidence 15 | cache empty dependencies; `anchorOf` dropping `k` | G | proved |
| `C16_links_enforced` | review finding 1; vLEI accreditation | vLEI policy, issuer 20 referencing a root credential issued to 30 | `chainFrom` ignoring `lk` | G | proved |
| `C17_registry_inception_must_stand` | review finding 6 | registry from a `vcp` at leaf 0 sealed at 1; issuer advances to 1 | skip `inception.stands` | G | proved |
| `C18_renewal_after_expiry` | review finding 5 | final admission at 10, bound 5, renew at 16 | `admit` refusing every occupied key | G | proved |
| `C19_live_admission_not_replaced` | review finding 5 | as C18 at 15 | `admit` overwriting unconditionally | G | proved |
| `C20_provisional_gate_window_witness` | review finding 2 (open decision) | constructed: provisional admission, issuer advance ≤ `k`, gate open | none (stated residual) | W | proved |

### Delegation — `DelegationGoals.lean`

| Theorem | Ruling | Witness of antecedent | Falsifying mutant | Kind | Status |
|---|---|---|---|---|---|
| `D1_no_cycles` | #292 "loops cannot happen" | root → external → QVI | `registerDelegated` ignoring `known` | G | proved |
| `D2_mint_iff` | #292 "who may mint one", "fail on the seal, never on the chain"; anchor | approval seal at index 0 of the parent's `ixn` | require the child's checkpoint | I | proved |
| `D3_mint_spends_nothing` | #292 "parent checkpoint as a reference input" | as D2 | mint advances parent | G | proved |
| `D4_delegated_leaf_needs_approval` | design "recursion becomes induction" | delegated register, then delegated advance | `advanceDelegated` without `takeCert` | G | proved |
| `D5_certificate_consumed_once` | #292 "the child's registration then consumes it" | as D4 | `takeCert` leaves token | G | proved |
| `D6_ancestry_reads_parents_only` | design "walks the parent fields … no signature checks" | two systems, same parents | consult `certs` | G | proved |
| `D7_depth_is_the_consumers` | #292 "depth is bounded by the consumer" | 2-generation chain, `n = 2` | refuse at exactly `n` | G | proved |
| `D8_seal_position_binds` | rules B1–B3 "`parent_seal_index` is not decoration" | seal at index 1 of a rotation | search the seal list | G | proved |
| `D9_absent_parent` | #292 "parent frozen or convicted after the fact" | parent `leave`, child present | `leave` cascading to children | G | proved |
| `D10_delegation_does_not_touch_the_tel` | design "Delegation does not touch the TEL" | parent `leave`, child's `iss` walk | `issuerWalk` requiring parent | G | proved |
| `D11_supersede_iff` | #391 "delegated … `update` of the latest leaf"; anchor | standing cert at latest sequence, later approval | supersede a non-delegated child | I | proved |
| `D12_plain_insert_only` | rule A1 at system level | reachable non-delegated checkpoint, any step | `supersedeDelegated` on `parent = none` | G | proved |
| `D13_overturned_approval_witness` | #292 "approvals can be overturned" (open item) | constructed: provisional mint, register, parent advance ≤ approving `sn` | none (explicit omission) | W | proved |
| `D14_supersede_needs_later_approval` | rules B1–B3 | leaf installed at parent (3, ixn, 0); certificate at (4, ixn, 0) supersedes, one at (2, ixn, 0) is refused | pass a fixed position | G | proved |
| `D15_installation_binds_event` | review: exact provenance | delegated advance with standing certificate | install a toad other than the event's | G | proved |
| `D16_reminted_approval_cannot_reinstall` | review: single use | consumed `old`, re-minted `old` on the live child | `before` reflexive | G | proved |
| `D17_stale_provisional_certificate_refused` | review finding 3 | `old` minted at parent's `ixn` 2, parent rotates at 2 before consumption | consumption skipping `certStands` | G | proved |
| `D18_rotation_supersedes_interaction` | rules B3, A2 | leaf from parent `ixn` 2 index 0; certificate from parent `rot` 2 index 0 | `before` comparing indices only | G | proved |

## Semantic-atom ledger

The finite fault model of `SEMANTIC-ATOMS.md` applies: guard relax/delete,
liveness force-false, evidence swap, effect omit/retain/stale/swap/misdirect,
refusal/terminal/composition edge remove/invent, one-sided correspondence
break. Every row is blocking because it decides an admission, a revocation
or a delegated key state.

### History and seal walk — `Statements/History.lean`

| Atom | Ruling | Model site / canonical mutant | Owning theorem(s) |
|---|---|---|---|
| HS-01 | #391 | `advance` back-pointer is the previous latest / `prev := none` | `H1_wf_reachable`, `H7_provisional_becomes_final` |
| HS-02 | #391 | `advance` strictly-later guard / accept `sn' ≤ latest` | `H1_wf_reachable`, `H8_non_delegated_insert_only` |
| HS-03 | rule A1/B | `supersede` parent guard / drop it | `H8_non_delegated_insert_only`, `H9_supersede_only_latest` |
| HS-04 | rule B | `supersede` only at latest / accept any `sn'` | `H9_supersede_only_latest`, `H5_final_is_stable` |
| HS-05 | rule B | `supersede` keeps `prev` / reset `prev` | `H9_supersede_only_latest`, `H1_wf_reachable` |
| HS-06 | Checkpoint D-033 | fresh epoch `cur + 1` on advance and supersede / reuse `cur` | `H1_wf_reachable`, `S4_current_key_thief_only_provisional` |
| HS-07 | #391 step 2 | `cover`: successor's `prev = e` / drop | `H2_cover_sound` |
| HS-08 | #391 step 2 | `cover`: `e ≤ k` / drop | `H2_cover_sound` |
| HS-09 | rule A0 | `cover`: `k < e'` / `k ≤ e'` | `H2_cover_sound`, `H6_superseding_excludes` |
| HS-10 | rule A0 | `cover`: provisional only when `e = latest` / any `e` | `H4_provisional_iff_latest`, `S4_current_key_thief_only_provisional` |
| HS-11 | #391 step 1 | `cover`: leaf `e` must exist / skip lookup | `H2_cover_sound`, `H4_provisional_iff_latest` |
| HS-12 | rule B2, #392 step 1 | `walkOn`: seal at the exact index / search the list | `S2_walk_binds_seal_at_index`, `D8_seal_position_binds` |
| HS-13 | #391 residual | `walkOn`: toad floor / drop | `S1_walk_needs_leaf_signature_and_receipts` |
| HS-14 | #392 step 3 | `walkOn`: `signed` at the leaf's epoch / at `cur` | `S1_walk_needs_leaf_signature_and_receipts`, `S3_walk_ignores_current_keys` |
| HS-15 | #391 receipt gate | `walkOn`: `receipted` at the leaf's epoch / drop | `S1_walk_needs_leaf_signature_and_receipts` |
| HS-16 | #392 step 1 (`rot`) | `walkOn`: establishment case `e = kel.sn` / drop | `S7_establishment_seal_is_own_leaf` |
| HS-17 | design | `walkOn` verdict is `cover`'s / constant | `S5_walk_verdict_is_cover_verdict`, `C6_provisional_iff_some_hop` |
| HS-18 | #392 step 1 | `sealWalk`: `tel.ri = rid` / drop | `S2_walk_binds_seal_at_index` |
| HS-19 | #392 step 1 | `sealOf` carries the digest / omit | `S6_seal_names_one_event` |
| HS-20 | rules B1–B3 | `supersede` requires a strictly later approval / drop `a.before appr` | `H10_older_approval_cannot_supersede`, `H9_supersede_only_latest` |
| HS-21 | rules B1–B3 | `advance` and `supersede` record the installing approval / keep the old one | `H9_supersede_only_latest`, `D14_supersede_needs_later_approval` |
| HS-22 | rule B3 | `before`: interaction yields to rotation at the same sequence / compare indices only | `D18_rotation_supersedes_interaction` |
| HS-23 | rule A2 | `before`: rotation never yields to interaction / symmetric kinds | `D18_rotation_supersedes_interaction`, `H10_older_approval_cannot_supersede` |
| HS-24 | #392 sequences | `sealWalk`: `wellFormed` / drop | `S8_walk_needs_well_formed_event` |
| HS-25 | design | `Anchor.stands`: same epoch at `e` / drop | `H12_moved_refutes_stands`, `C17_registry_inception_must_stand` |
| HS-26 | design | `Anchor.stands`: `cover` under the proof / constant true | `H11_final_anchor_stands`, `D17_stale_provisional_certificate_refused` |
| HS-27 | design | `Anchor.moved`: evidence leaf in `(e, k]` / above `k` | `H12_moved_refutes_stands`, `C9_evict_iff` |
| HS-28 | design | `anchorOf` records `k = kel.sn` / record `e` | `C15_provisional_admission_evictable_after_superseding` |

### Mirror — `Statements/Mirror.lean`

| Atom | Ruling | Model site / canonical mutant | Owning theorem(s) |
|---|---|---|---|
| MR-01 | #392 `vcp` row | `open` requires kind `vcp` / accept `iss` | `M7_open_iff` |
| MR-02 | #392 `vcp` row | `open` requires the walk / trust `issuer` | `M5_registry_bound_to_issuer`, `M7_open_iff` |
| MR-03 | #392 one UTxO per registry | `open` refuses an existing registry / overwrite | `M7_open_iff`, `M2_revocation_is_permanent` |
| MR-04 | #392 datum | `open` records issuer, `rid = tel.i`, the walk's anchor, empty set / seed the set | `M5_registry_bound_to_issuer`, `M7_open_iff`, `M13_inception_is_a_walk_anchor` |
| MR-05 | design | `push` requires the registry / create on push | `M6_push_iff`, `M11_miss_fails_closed` |
| MR-06 | #392 `rev` row | `push` requires kind `rev` / accept `iss` | `M6_push_iff` |
| MR-07 | #392 "issuer's own seal" | `push` walks against the registry's issuer / any checkpoint | `M1_only_the_issuer_revokes`, `M6_push_iff` |
| MR-08 | #392 "fails on insert" | `push` refuses a present SAID / re-insert | `M3_duplicate_push_refused` |
| MR-09 | #392 `rev` row | `push` inserts exactly `tel.i` / insert `tel.ri` | `M1_only_the_issuer_revokes`, `M4_pushes_commute` |
| MR-10 | design "fails closed" | no action deletes or closes / a delete edge | `M2_revocation_is_permanent`, `M9_superseded_push_over_revokes` |
| MR-11 | design | `push` accepts a provisional walk / require final | `M9_superseded_push_over_revokes`, `M6_push_iff` |
| MR-12 | design | `miss` fails closed on `none` / `true` | `M11_miss_fails_closed`, `C5_unopened_registry_refuses` |
| MR-13 | #392 "no current-key check" | mirror steps never read `cur` / guard on `cur` | `M8_mirror_ignores_current_keys` |
| MR-14 | review finding 6 | `reanchor` requires the walk of a `vcp` naming the registry / trust the caller | `M12_reanchor_iff`, `M13_inception_is_a_walk_anchor` |
| MR-15 | review finding 6 | `reanchor` keeps issuer and set / reset the set | `M12_reanchor_iff`, `M2_revocation_is_permanent` |

### Credential — `Statements/Credential.lean`

| Atom | Ruling | Model site / canonical mutant | Owning theorem(s) |
|---|---|---|---|
| CR-01 | primer pin 1 | `hopVerdict`: `saidOf body = said` / drop | `C3_integrity_and_edges` |
| CR-02 | primer pin 1 | `hopVerdict`: `edge = parent` / drop | `C3_integrity_and_edges` |
| CR-03 | #391 seal walk | `hopVerdict`: `iss` naming the credential / accept any `i` | `C2_every_hop_sealed_by_its_issuer` |
| CR-04 | primer pin 3 | `hopVerdict`: issuer checkpoint required / presenter's | `C2_every_hop_sealed_by_its_issuer` |
| CR-05 | design per-link absence | `hopVerdict`: registry exists and is the issuer's / missing = clean | `C5_unopened_registry_refuses` |
| CR-06 | primer pin 4 | `hopVerdict`: unrevoked / drop | `C4_revoked_link_refuses`, `C10_cascade_at_gate` |
| CR-07 | #391 seal walk | walk for the credential's own registry / any `rid` | `C2_every_hop_sealed_by_its_issuer` |
| CR-08 | primer pin 2 | last hop: no edge, root issuer / drop root | `C1_admitted_chain_is_pinned` |
| CR-09 | primer pin 2 | schema pinned by position / ignore | `C1_admitted_chain_is_pinned` |
| CR-10 | verifier bound | depth bound / drop | `C1_admitted_chain_is_pinned` |
| CR-11 | design | `meet` final only when all final / any | `C6_provisional_iff_some_hop` |
| CR-12 | design cage | `admit` records deps from `Hop.dep` / empty deps | `C14_admit_iff`, `C15_provisional_admission_evictable_after_superseding` |
| CR-13 | design eviction | `evict` requires a moved dep / unconditional | `C8_final_never_evicted`, `C9_evict_iff` |
| CR-14 | rule B | `Dep.moved`: epoch changed at `e` / drop | `C9_evict_iff` |
| CR-15 | rule A0 | `Dep.moved`: evidence leaf in `(e, k]` / `(e, ∞)` | `C9_evict_iff`, `C8_final_never_evicted` |
| CR-16 | defi-gate freshness | `gate`: `now ≤ admittedAt + notAfter` / drop | `C11_gate_iff` |
| CR-17 | design cascade | `gate`: `miss` per link / leaf only | `C10_cascade_at_gate`, `C11_gate_iff` |
| CR-18 | design "cheap lookup" | `gate` reads no checkpoint / re-walk | `C12_gate_reads_no_checkpoint` |
| CR-19 | design "never mixed" | admission ignores `cur` / check `cur` | `C7_admission_ignores_current_keys` |
| CR-20 | defi-gate admission under the acting entity | `admit` requires the leaf's issuee to be the key / drop | `C13_admission_binds_actor`, `C14_admit_iff` |
| CR-21 | review finding 1 | `chainFrom` requires the policy's link per edge / ignore `lk` | `C16_links_enforced`, `C1_admitted_chain_is_pinned` |
| CR-22 | review finding 6 | `hopVerdict` requires the registry's inception to stand / skip | `C17_registry_inception_must_stand` |
| CR-23 | review finding 5 | `admit` replaces only an expired admission / overwrite | `C19_live_admission_not_replaced`, `C14_admit_iff` |
| CR-24 | review finding 5 | `admit` accepts an expired key / refuse occupied | `C18_renewal_after_expiry` |
| CR-25 | review finding 5 | `expire` requires expiry / unconditional | `C18_renewal_after_expiry`, `C19_live_admission_not_replaced` |

### Delegation — `Statements/Delegation.lean`

| Atom | Ruling | Model site / canonical mutant | Owning theorem(s) |
|---|---|---|---|
| DL-01 | #292 reference input | `mint` requires the parent's checkpoint / skip | `D2_mint_iff`, `D9_absent_parent` |
| DL-02 | #292 "presents that seal" | `mint` requires the approval walk / skip | `D2_mint_iff`, `D4_delegated_leaf_needs_approval` |
| DL-03 | #292 token name | `mint` refuses a duplicate name / allow | `D2_mint_iff`, `D5_certificate_consumed_once` |
| DL-04 | rules B1–B3 | `mint` records sequence, kind, index / zero them | `D8_seal_position_binds` |
| DL-05 | #292 contention | `mint` spends nothing / advance parent | `D3_mint_spends_nothing` |
| DL-06 | #292 "registration consumes it" | `registerDelegated` needs the `sn = 0` certificate / skip | `D4_delegated_leaf_needs_approval` |
| DL-07 | #292 "inherits the parent named at inception" | `registerDelegated` respects `known` / ignore | `D1_no_cycles` |
| DL-08 | same | `registerPlain` respects `known` / ignore | `D1_no_cycles` |
| DL-09 | design "paid once per rotation" | `advanceDelegated` consumes the certificate of the parent's name / skip | `D4_delegated_leaf_needs_approval`, `D5_certificate_consumed_once` |
| DL-10 | rule A1 | `advancePlain` refuses a delegated child / accept | `D12_plain_insert_only` |
| DL-11 | rule B | `supersedeDelegated` only delegated, via `supersede` / on `parent = none` | `D11_supersede_iff`, `D12_plain_insert_only` |
| DL-12 | #292 "frozen or convicted after the fact" | `leave` touches one AID / cascade | `D9_absent_parent`, `D10_delegation_does_not_touch_the_tel` |
| DL-13 | design "no signature checks" | `ancestorWithin` reads parent fields only / consult certs | `D6_ancestry_reads_parents_only` |
| DL-14 | #292 "where it stops" | `ancestorWithin` stops at an absent checkpoint / skip over | `D9_absent_parent` |
| DL-15 | #292 "depth bounded by the consumer" | `ancestorWithin` monotone in the bound / refuse at `n` | `D7_depth_is_the_consumers` |
| DL-16 | design "does not touch the TEL" | `issuerWalk` reads the issuer's own checkpoint / require parent | `D10_delegation_does_not_touch_the_tel` |
| DL-17 | rules B1–B3 | delegated steps pass the certificate's approval to the history / pass a constant | `D14_supersede_needs_later_approval`, `D11_supersede_iff` |
| DL-18 | review finding 3 | `mint` records the walk's anchor / a constant anchor | `D2_mint_iff`, `D17_stale_provisional_certificate_refused` |
| DL-19 | review finding 3 | consumption requires `certStands` / skip | `D17_stale_provisional_certificate_refused`, `D15_installation_binds_event` |
| DL-20 | review finding 3 | `certStands` trusts a final certificate without the parent / require parent | `D9_absent_parent`, `D11_supersede_iff` |
| DL-21 | review: provenance | delegated installs use the event's toad / a constant | `D15_installation_binds_event`, `D4_delegated_leaf_needs_approval` |

## Explicit omissions and residuals (creator claims needing a ruling)

- **Provisional-gate window** (review finding 2): between an issuer's
  superseding rotation and the permissionless eviction, a provisional
  admission still gates (C20). Bounded by the freshness bound; closed by
  eviction on evidence. The alternative — the gate reading the issuer
  checkpoint of every provisional dependency — is an open design decision.
- **Overturned approvals** (#292 open item): an already-installed child
  leaf stands after the parent supersedes the approving event (D13); a
  stale certificate installs nothing (D17). No bonded challenge.
- **Rule C/C1**: recursive precedence up the delegation chain is not
  represented; a delegated rotation whose precedence is decided only there
  is refused (fail closed).
- **Lifecycle composition**: `leave` merges parked and convicted and
  permits re-registration; conviction terminality and revival from the
  parked key state are the checkpoint machine's guarantees, not this
  model's. Revival is a fresh registration with its inception certificate.
- **Revocation freshness** (#398): push latency, stated not enforced (M10).
- **Attestation-token cuts** (#397), fees, min-ADA, blinded TEL state: not
  modelled.
