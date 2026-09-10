# Statement and semantic-atom ledgers — ACDC, TEL mirror, delegation (unproven)

STATEMENTS mode, authored 2026-09-10 against `main@88e9309`. Authority:
`docs/design/credential-verification.md` (decision recorded 2026-09-10),
[#391](https://github.com/lambdasistemi/cardano-keri/issues/391),
[#392](https://github.com/lambdasistemi/cardano-keri/issues/392),
[#292](https://github.com/lambdasistemi/cardano-keri/issues/292), #31 as
amended by #391, `docs/acdc-primer.md`, `docs/design/defi-gate.md`, and the
KERI superseding rules A0/A1/B/B2.

Every theorem in `CardanoKeri/Statements/*Goals.lean` ends in `sorry`. The
rows below are **creator claims** for an independent statement audit
(`lean-auditor`), never self-certified coverage: each theorem names the
reachable witness of its antecedent and the single-atom mutant expected to
falsify it. Statement hashes are frozen only after that audit returns ready;
proof work (`PROOFS`) starts after the freeze.

Build: `cd lean && lake build CardanoKeriStatements` (warnings: 57 `sorry`).
The default target `lake build` does not include this library, so the
zero-`sorry` gate of `scripts/check-lean-traceability.sh` is unaffected.

Repair 1 (2026-09-10, four audit findings): admission binds the actor to
the leaf credential's issuee (C13, C14); rule-B superseding compares the
approval's position in the parent's log and refuses an older approval (H9,
H10, D11, D14; `Checkpoint.approval`); the insert-only statements take a
well-formedness or reachability premise (H8, D12); stored dependencies are
tied to eviction after superseding (C14, C15).

## Model surface

| Module | What it models | Executable core |
|---|---|---|
| `Statements/History.lean` | key-state history leaves with back-pointer; `advance` (insert), `supersede` (rule B update); the range proof `cover`; the seal walk `walkOn` / `sealWalk` | `hstep`, `cover`, `walkOn`, `sealWalk` |
| `Statements/Mirror.lean` | per-registry revoked set; `open` from a sealed `vcp`; permissionless `push` of a sealed `rev`; `miss` | `Mirror.stepFn`, `miss` |
| `Statements/Credential.lean` | ACDC chain admission (integrity, edges, schema, root pin, depth, `iss` walk, absence); the cage with provisional dependencies; `evict`; `gate` | `admitChain`, `Credential.stepFn`, `gate` |
| `Statements/Delegation.lean` | approval certificates minted by the seal walk on the parent; consumed by `dip`/`drt`; rule-B superseding; `leave`; the ancestry walk | `Delegation.stepFn`, `ancestorWithin` |

Modelling assumptions, stated in the module docstrings: no cryptography
(epochs for key states, decidable `signed`/`receipted`, digests as functions
with injectivity hypothesised where needed); no MPF (a root is the map it
commits to); no bonds, fees or attestation-token cuts (#397); the actor's
own threshold is `Checkpoint.consumableState`; issuer/issuee relations
between hops are a policy hook; revival of a delegated identity is a fresh
registration.

## Theorem ledger

Columns: theorem; the ruling or design sentence it answers to; a reachable
witness that makes the antecedent true; the single-atom mutant expected to
falsify it; kind (`G` guarantee, `I` public inversion, `W` witness of a
stated limit — an existential, not a guarantee).

### History and seal walk — `HistoryGoals.lean`

| Theorem | Ruling | Witness of antecedent | Falsifying mutant | Kind |
|---|---|---|---|---|
| `H1_wf_reachable` | #391 "insert-only", leaf `prev_sn` | register, advance to 12, advance to 40 | `advance` with `prev := none` | G |
| `H2_cover_sound` | #391 "no rotation sits between `e` and `k`" | leaves 0, 12, 40; `cover 12 17 (some 40)` | drop `k < e'` | G |
| `H3_cover_complete` | #391 "or `e == native_sn`" | leaves 0, 12; `Governs 12 17` | refuse `succ = none` | G |
| `H4_provisional_iff_latest` | rule A0, design "provisional" | leaf 12 latest, `cover 12 17 none` | `final` on `succ = none` | G |
| `H5_final_is_stable` | design "its admission is final" | `cover 12 17 (some 40) = final`, then advance to 50 | `supersede` touching non-latest leaf | G |
| `H6_superseding_excludes` | rule A0, design "superseding recovery" | `cover 12 17 none = provisional`, advance to 15 | `k ≤ e'` in `cover` | G |
| `H7_provisional_becomes_final` | #391 step 2 | `cover 12 17 none = provisional`, advance to 40 | wrong back-pointer on advance | G |
| `H8_non_delegated_insert_only` | rule A1 | well-formed non-delegated, any step | `supersede` without `parent` guard | G |
| `H9_supersede_only_latest` | rules B, B2, #391 "MPF `update` of the latest leaf" | delegated at latest 12 installed by approval (3, 0), `supersede 12` with (4, 0) | accept `sn' ≠ latest` | G |
| `H10_older_approval_cannot_supersede` | rule B2, feasibility report §3 | leaf installed by (3, 0), certificate at (2, 0) | drop `a.before appr` | G |
| `S1_walk_needs_leaf_signature_and_receipts` | #392 step 3, #391 "receipt gate" | walk with `signed`/`receipted` true at leaf 12 | drop `receipted` | G |
| `S2_walk_binds_seal_at_index` | #391 "without every link", #392 step 1 | seal at index 0 of an `ixn` at 17 | compare `seal.i` only | G |
| `S3_walk_ignores_current_keys` | design "never mixed" | any walk | check `env.signed c.cur` | G |
| `S4_current_key_thief_only_provisional` | primer Q4 "killed by owner rotation" | env signing only at `cur`; walk on latest leaf | `final` on latest leaf | G |
| `S5_walk_verdict_is_cover_verdict` | design verdict travels with the walk | any successful walk | constant verdict | G |
| `S6_seal_names_one_event` | #391 "a credential it never sealed" | two walks, same `ixn`, same index | `sealOf` without digest | G |
| `S7_establishment_seal_is_own_leaf` | #392 "for a `rot` the covering leaf is the event itself" | `rot` at 12 sealing a `vcp` | drop `w.e = w.kel.sn` | G |

### Mirror — `MirrorGoals.lean`

| Theorem | Ruling | Witness of antecedent | Falsifying mutant | Kind |
|---|---|---|---|---|
| `M1_only_the_issuer_revokes` | #392 "the issuer's own cryptography is the permission" | register, open, push one `rev` | `push` without `sealWalk` | G |
| `M2_revocation_is_permanent` | design "over-revokes and fails closed" | registry with one SAID, any step | a delete action | G |
| `M3_duplicate_push_refused` | #392 "duplicate pushes fail on `insert`" | push the same `rev` twice | re-insert resets set | G |
| `M4_pushes_commute` | #392 "converges however it is filled" | two `rev`s, distinct SAIDs | position-recording accumulator | G |
| `M5_registry_bound_to_issuer` | #392 registry row: "registry id bound to issuer AID" | open from a `vcp` | trust the `issuer` argument | G |
| `M6_push_iff` | #392 "no owner authorization, no current-key check" | as M1 | guard on `cur` | I |
| `M7_open_iff` | #392 `vcp` row | as M5 | accept `iss` as inception | I |
| `M8_mirror_ignores_current_keys` | #392 "current keys cannot vouch for past events" | open/push after `setCur` | require `signed c.cur` | G |
| `M9_superseded_push_over_revokes` | design "revocations pushed under them stay in the set" | provisional push, then advance at or below `k` | evict revocations on superseding | G |
| `M10_freshness_unenforced` | #392 "absence in the mirror is not absence in the KEL" | constructed: sealed `rev`, never pushed | none (stated limit, #398) | W |
| `M11_miss_fails_closed` | design "each against its own registry" | unopened registry | `true` on `none` | G |

### Credential — `CredentialGoals.lean`

| Theorem | Ruling | Witness of antecedent | Falsifying mutant | Kind |
|---|---|---|---|---|
| `C1_admitted_chain_is_pinned` | primer Q4 pin 2, verifier bound 4 | 2-hop chain to the root | drop root check on last hop | G |
| `C2_every_hop_sealed_by_its_issuer` | primer Q4 pin 3, #31 amended | as C1 | walk against presenter's checkpoint | G |
| `C3_integrity_and_edges` | primer Q4 pin 1, "swap parent breaks edge SAIDs" | as C1 | ignore `edge` | G |
| `C4_revoked_link_refuses` | primer pin 4 "cascade" | chain with parent SAID pushed | mirror check on leaf only | G |
| `C5_unopened_registry_refuses` | design "one absence proof per link" | hop whose registry is unopened | missing registry = nothing revoked | G |
| `C6_provisional_iff_some_hop` | design "provisional when e is the latest leaf" | one hop on its issuer's latest leaf | `meet` final on any final | G |
| `C7_admission_ignores_current_keys` | design "never mixed" | any chain, `setCur` | `hopVerdict` checking `cur` | G |
| `C8_final_never_evicted` | design "evicts a provisional admission" | final admission, any later step | `Dep.moved` ignoring verdict | G |
| `C9_evict_iff` | design "inserts a leaf at or below that sequence number" | provisional admission, issuer advance ≤ `k` | evict on leaf above `k` | I |
| `C10_cascade_at_gate` | design "a revoked QVI credential fails every chain below it" | admitted chain, push of a parent SAID | gate on leaf registry only | G |
| `C11_gate_iff` | defi-gate "cheap lookup + freshness bound" | fresh admission, all links absent | drop freshness bound | I |
| `C12_gate_reads_no_checkpoint` | design "with no signature checks" | any gate | re-walk a seal | G |
| `C13_admission_binds_actor` | defi-gate: admission cached under the acting entity | leaf issued to 7, admitted under 7; refused under 999 | drop the issuee guard | G |
| `C14_admit_iff` | design cage | as C13 | cache empty dependencies | I |
| `C15_provisional_admission_evictable_after_superseding` | design "evicts a provisional admission when the issuer's checkpoint later inserts a leaf at or below" | provisional hop on leaf 12 sealing at 17, issuer advances to 15 | cache empty dependencies; `Hop.dep` dropping `k` | G |

### Delegation — `DelegationGoals.lean`

| Theorem | Ruling | Witness of antecedent | Falsifying mutant | Kind |
|---|---|---|---|---|
| `D1_no_cycles` | #292 "loops cannot happen" | root → external → QVI | `registerDelegated` ignoring `known` | G |
| `D2_mint_iff` | #292 "who may mint one", "fail on the seal, never on the chain" | approval seal at index 0 of the parent's `ixn` | require the child's checkpoint | I |
| `D3_mint_spends_nothing` | #292 "parent checkpoint as a reference input" | as D2 | mint advances parent | G |
| `D4_delegated_leaf_needs_approval` | design "recursion becomes induction" | delegated register, then delegated advance | `advanceDelegated` without `takeCert` | G |
| `D5_certificate_consumed_once` | #292 "the child's registration then consumes it" | as D4 | `takeCert` leaves token | G |
| `D6_ancestry_reads_parents_only` | design "walks the parent fields … no signature checks" | two systems, same parents | consult `certs` | G |
| `D7_depth_is_the_consumers` | #292 "depth is bounded by the consumer" | 2-generation chain, `n = 2` | refuse at exactly `n` | G |
| `D8_seal_position_binds` | #292 rule B2 "`parent_seal_index` is not decoration" | seal at index 1 | search the seal list | G |
| `D9_absent_parent` | #292 "parent frozen or convicted after the fact" | parent `leave`, child present | `leave` cascading to children | G |
| `D10_delegation_does_not_touch_the_tel` | design "Delegation does not touch the TEL" | parent `leave`, child's `iss` walk | `issuerWalk` requiring parent | G |
| `D11_supersede_iff` | #391 "delegated … `update` of the latest leaf" | cert at latest sequence, later approval | supersede a non-delegated child | I |
| `D12_plain_insert_only` | rule A1 at system level | reachable non-delegated checkpoint, any step | `supersedeDelegated` on `parent = none` | G |
| `D13_overturned_approval_witness` | #292 "approvals can be overturned" (open item) | constructed: provisional mint, then parent advance ≤ approving `sn` | none (explicit omission) | W |
| `D14_supersede_needs_later_approval` | rule B2, feasibility report §3 | leaf installed at parent (3, 0); certificate at (4, 0) supersedes, one at (2, 0) is refused | pass a fixed position instead of the certificate's | G |

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
| HS-20 | rule B2 | `supersede` requires a strictly later approval / drop `a.before appr` | `H10_older_approval_cannot_supersede`, `H9_supersede_only_latest` |
| HS-21 | rule B2 | `advance` and `supersede` record the installing approval / keep the old one | `H9_supersede_only_latest`, `D14_supersede_needs_later_approval` |

### Mirror — `Statements/Mirror.lean`

| Atom | Ruling | Model site / canonical mutant | Owning theorem(s) |
|---|---|---|---|
| MR-01 | #392 `vcp` row | `open` requires kind `vcp` / accept `iss` | `M7_open_iff` |
| MR-02 | #392 `vcp` row | `open` requires the walk / trust `issuer` | `M5_registry_bound_to_issuer`, `M7_open_iff` |
| MR-03 | #392 one UTxO per registry | `open` refuses an existing registry / overwrite | `M7_open_iff`, `M2_revocation_is_permanent` |
| MR-04 | #392 datum | `open` records issuer, `rid = tel.i`, empty set / seed the set | `M5_registry_bound_to_issuer`, `M7_open_iff` |
| MR-05 | design | `push` requires the registry / create on push | `M6_push_iff`, `M11_miss_fails_closed` |
| MR-06 | #392 `rev` row | `push` requires kind `rev` / accept `iss` | `M6_push_iff` |
| MR-07 | #392 "issuer's own seal" | `push` walks against the registry's issuer / any checkpoint | `M1_only_the_issuer_revokes`, `M6_push_iff` |
| MR-08 | #392 "fails on insert" | `push` refuses a present SAID / re-insert | `M3_duplicate_push_refused` |
| MR-09 | #392 `rev` row | `push` inserts exactly `tel.i` / insert `tel.ri` | `M1_only_the_issuer_revokes`, `M4_pushes_commute` |
| MR-10 | design "fails closed" | no action deletes or closes / a delete edge | `M2_revocation_is_permanent`, `M9_superseded_push_over_revokes` |
| MR-11 | design | `push` accepts a provisional walk / require final | `M9_superseded_push_over_revokes`, `M6_push_iff` |
| MR-12 | design | `miss` fails closed on `none` / `true` | `M11_miss_fails_closed`, `C5_unopened_registry_refuses` |
| MR-13 | #392 "no current-key check" | mirror steps never read `cur` / guard on `cur` | `M8_mirror_ignores_current_keys` |

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
| CR-15 | rule A0 | `Dep.moved`: leaf in `(e, k]` / `(e, ∞)` | `C9_evict_iff`, `C8_final_never_evicted` |
| CR-16 | defi-gate freshness | `gate`: `now ≤ admittedAt + notAfter` / drop | `C11_gate_iff` |
| CR-17 | design cascade | `gate`: `miss` per link / leaf only | `C10_cascade_at_gate`, `C11_gate_iff` |
| CR-18 | design "cheap lookup" | `gate` reads no checkpoint / re-walk | `C12_gate_reads_no_checkpoint` |
| CR-19 | design "never mixed" | admission ignores `cur` / check `cur` | `C7_admission_ignores_current_keys` |
| CR-20 | defi-gate admission under the acting entity | `admit` requires the leaf's issuee to be the key / drop | `C13_admission_binds_actor`, `C14_admit_iff` |

### Delegation — `Statements/Delegation.lean`

| Atom | Ruling | Model site / canonical mutant | Owning theorem(s) |
|---|---|---|---|
| DL-01 | #292 reference input | `mint` requires the parent's checkpoint / skip | `D2_mint_iff`, `D9_absent_parent` |
| DL-02 | #292 "presents that seal" | `mint` requires the approval walk / skip | `D2_mint_iff`, `D4_delegated_leaf_needs_approval` |
| DL-03 | #292 token name | `mint` refuses a duplicate name / allow | `D2_mint_iff`, `D5_certificate_consumed_once` |
| DL-04 | rule B2 | `mint` records `parentSn`, `sealIdx`, verdict / zero them | `D8_seal_position_binds` |
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
| DL-17 | rule B2 | delegated steps pass the certificate's `(parentSn, sealIdx)` to the history / pass a constant | `D14_supersede_needs_later_approval`, `D11_supersede_iff` |

## Explicit omissions (creator claims needing a ruling)

- **Overturned approvals** (#292 open item): modelled as `D13`, a witness
  that the child's leaf stands. No bonded challenge; no eviction of
  delegated leaves.
- **Registry opened from a superseded `vcp`**: the registry stores no
  verdict; harmlessness rests on every `iss` under that registry being on
  the same disputed branch. Not stated as a theorem.
- **Issuer/issuee relation between hops** (QVI → LE → OOR-AUTH → OOR):
  schema-specific; the policy pins schemas only.
- **Revival of a delegated identity** is a fresh registration with its
  inception certificate, not a rotation from the parked key state.
- **Attestation-token cuts** (#397), fees, min-ADA, blinded TEL state: not
  modelled.
