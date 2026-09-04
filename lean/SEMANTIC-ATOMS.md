# Frozen semantic-atom ledger — issue 365

Frozen against `main@9b2e6b88937707cc2c571ae1e9e5f112dc248a30` on
2026-09-04. Authority is D-022…D-040 plus the verbatim 2026-09-02/03 rulings
preserved in `docs/design/registry-as-mpfs.md`, including MPFS #79/#100/#101/
#102. Every row is blocking because it affects chain state, money, signatures,
or the correspondence through which those properties are executed.

The finite operator set is guard relax/delete, liveness force-false, evidence
swap, effect omit/retain/stale/swap/misdirect, refusal/terminal/composition edge
remove/invent, and one-sided correspondence break. The campaign stops after one
right-reason killed mutant per row and one witness/kill per theorem row below.
Equivalent or shadowed mutants are replaced or leave the row `BLOCKED`. This is
a finite declared fault model, not a claim that no other mutant can survive.

## Semantic atoms — Checkpoint

The source/model identity is `CardanoKeri/Checkpoint.lean`; the existing mutant
name is retained as the canonical single-edit identity.

| Atom | Ruling | Model site / canonical mutant | Owning theorem(s) | Severity |
|---|---|---|---|---|
| CP-01 | D-034 | `Step.freeze` short-pool guard / M1 | `T15_b_leaves_only_by_freeze`, `T5_freeze_enabled` | blocking |
| CP-02 | D-034 | `Step.freeze` not-frozen guard / M2 | `T5_freeze_enabled`, `T6_component_conservation` | blocking |
| CP-03 | D-022,D-023 | `Step.poison` clean guard / M3 | `T4_poisoned_blocks_quorum_and_freeze`, `T5_poison_enabled` | blocking |
| CP-04 | D-034 | `Step.topUp` preserves `bornAt` / M4 | `T14_pool_increases_only_by_topup` | blocking |
| CP-05 | D-030,D-031 | `Step.convict` duplicity guard / M5 | `T12_convict_exact`, `T5_convict_enabled` | blocking |
| CP-06 | D-030,D-040 | `Step.convictParked` duplicity guard / M6 | `T12_convict_parked_exact`, `T5_convict_parked_enabled` | blocking |
| CP-07 | D-030,D-040 | parked conviction pays nothing / M7 | `T12_convict_parked_exact`, `T16_payments_are_named` | blocking |
| CP-08 | D-032,D-034 | conviction refunds held freeze bond / M8 | `T12_convict_exact`, `T6_component_conservation` | blocking |
| CP-09 | D-034,D-040 | deposit clears frozen / M9 | `T5_deposit_on_full_is_keep`, `T6_component_conservation` | blocking |
| CP-10 | D-040 | full-bond deposit preserves `bornAt` / M10 | `T10_only_deposit_restores`, `T5_deposit_on_full_is_keep` | blocking |
| CP-11 | D-034,D-040 | deposit brings only missing B / M11 | `T5_deposit_on_full_is_keep`, `T6_component_conservation` | blocking |
| CP-12 | D-038 | deposit intent bound to deposit / M12 | `T5_every_bond_option`, `T6_intent_requires_new_keys` | blocking |
| CP-13 | D-032,D-038 | changed refund address is signed / M13 | `T5_keep_is_rotated`, `T6_refund_change_requires_new_keys` | blocking |
| CP-14 | D-038,D-039 | only keep-none has empty intent / M14 | `T16_copied_reap_refused`, `T6_intent_requires_new_keys` | blocking |
| CP-15 | D-036,D-040 | revival sequence strictly advances / M15 | `T1_reopen_strict`, `T5_reopen_enabled` | blocking |
| CP-16 | D-036,D-040 | revival evidence bound to parked key state / M16 | `T4_current_key_thief_cannot_revive`, `T5_reopen_enabled` | blocking |
| CP-17 | D-040 | revival increments epoch / M17 | `T2_close_and_reopen_open_epochs` | blocking |
| CP-18 | D-036,D-040 | revival resets juvenility to now / M18 | `T10_reopen_is_juvenile` | blocking |
| CP-19 | D-034,D-040 | revival starts unfrozen / M19 | `T10_reopen_is_juvenile`, `T6_component_conservation` | blocking |
| CP-20 | D-036,D-040 | revival brings conviction bond / M20 | `T10_reopen_is_juvenile`, `T6_component_conservation` | blocking |
| CP-21 | D-036,D-040 | close parks next epoch / M21 | `T16_close_destination`, `T2_close_and_reopen_open_epochs` | blocking |
| CP-22 | D-036,D-040 | close parks reached sequence / M22 | `T16_parked_hash_is_the_closed_checkpoints` | blocking |
| CP-23 | D-038,D-039 | close intent binds payee / M23 | `T16_copied_reap_refused`, `T16_close_destination` | blocking |
| CP-24 | D-038,D-039 | close intent cannot be keep / M24 | `T16_copied_reap_refused`, `T6_intent_requires_new_keys` | blocking |
| CP-25 | D-032,D-039 | premium goes to signed payee / M25 | `T16_close_destination`, `T16_copied_reap_refused` | blocking |
| CP-26 | D-032,D-038 | refund goes to signed chosen address / M26 | `T16_close_destination` | blocking |
| CP-27 | D-032,D-034 | paid premium is deducted from pool / M27 | `T16_close_destination`, `T6_component_conservation` | blocking |
| CP-28 | D-036 | close needs witnessed rotation / M28 | `T16_close_needs_rotation`, `T4_current_key_thief_cannot_park` | blocking |
| CP-29 | D-036,D-039 | short-pool close remains enabled / M29 | `T5_close_enabled` | blocking |
| CP-30 | D-034,D-040 | keep-shaped rotation preserves age / M30 | `T5_keep_is_rotated`, `T5_deposit_on_full_is_keep` | blocking |
| CP-31 | D-034 | premium exists iff pool covers P / M31 | `T16_close_destination`, `T5_keep_is_rotated` | blocking |
| CP-32 | D-040 | parked state reads parked leaf/hash / M32 | `T8_leaf_states`, `T8_utxo_iff_active` | blocking |
| CP-33 | D-030,D-040 | convicted state reads convicted leaf / M33 | `T8_leaf_states` | blocking |
| CP-34 | D-036,D-037,D-040 | system revival requires parked leaf / M34 | `T8_leaf_never_absent_again`, `T8_sysstep_partition` | blocking |
| CP-35 | D-036,D-037,D-040 | close changes leaf partition / M35 | `T8_edges_leave_the_leaf` | blocking |
| CP-36 | D-034,D-040 | `Live.bHeld` reflects frozen state / M36 | `T10_bonds_are_observable`, `T15_b_returns_only_by_deposit` | blocking |
| CP-37 | D-034 | consumer predicate includes not-frozen / M37 | `consumableStateB_iff` | blocking |
| CP-38 | D-040 | parked identity holds no D / M38 | `T10_parked_holds_nothing`, `T6_dreg_never_a_fee` | blocking |
| CP-39 | D-036,D-038,D-039 | current-key thief cannot park / M39 | `T4_current_key_thief_cannot_park`, `T16_copied_reap_refused` | blocking |
| CP-40 | D-030,D-040 | revival clears accumulated poison / M40 | `trace_poison_fold` | blocking |

## Semantic atoms — Registry

The source/model identity is `CardanoKeri/Registry.lean`; ruling numbers refer
to the verbatim list and R1…R14 guarantees in `registry-as-mpfs.md`.

| Atom | Ruling | Model site / canonical mutant | Owning theorem(s) | Severity |
|---|---|---|---|---|
| RG-01 | 3,R1 | register absence guard / M1 | `processOne_inv`, `processOne_register_registered` | blocking |
| RG-02 | 3,R1 | register inception evidence / M2 | `processOne_inv`, `processOne_leaf_mono` | blocking |
| RG-03 | 6,R1 | revival rotation evidence / M3 | `processOne_inv` | blocking |
| RG-04 | 3,6,R1 | revival no-checkpoint coupling / M4 | `processOne_inv` | blocking |
| RG-05 | 6,R1 | go operation requires active leaf / M5 | `processOne_inv`, `processOne_leaf_mono` | blocking |
| RG-06 | 1,6,R14 | dormant conviction duplicity / M6 | `R14_convict_dormant_needs_proof`, `R14_convict_in_batch_needs_proof` | blocking |
| RG-07 | 6,R9 | go-request rejection veto / M7 | `R9_go_never_rejected`, `rejectOne_inv` | blocking |
| RG-08 | R9,R10 | rejection needs rejectable phase / M8 | `R9_reject_needs_rejectable`, `R9_reject_enabled` | blocking |
| RG-09 | R9,R10 | process needs phase 1 / M9 | `processOne_inv`, `R14_convict_at_position` | blocking |
| RG-10 | R7 | fold generation equality / M10 | `R7_stale_fold_refused`, `R7_one_fold_per_generation` | blocking |
| RG-11 | #100,R8 | empty fold refused / M11 | `R8_empty_fold_refused` | blocking |
| RG-12 | #100,R5,R8 | plugin swap refused / M12 | `R5_plugin_pinned`, `R8_plugin_swap_refused` | blocking |
| RG-13 | R6 | fold increments generation / M13 | `R6_fold_advances`, `inv_step` | blocking |
| RG-14 | R9 | retract needs phase 2 / M14 | `R9_retract_needs_phase2`, `inv_step` | blocking |
| RG-15 | 8,R13 | bonded/live checkpoint not reaped / M15 | `R13_live_never_reaped` | blocking |
| RG-16 | 8,R13 | stranger grace-window guard / M16 | `R13_parked_needs_grace`, `R13_owner_reaps_early` | blocking |
| RG-17 | 6,8,R9,R13 | go-request dated `far` / M17 | `R13_tomb_reaped`, `inv_step` | blocking |
| RG-18 | 6,8,R13 | reap removes checkpoint / M18 | `R13_tomb_reaped`, `inv_step` | blocking |
| RG-19 | 1,6,R14 | checkpoint conviction duplicity / M19 | `R14_convictCkpt_needs_proof` | blocking |
| RG-20 | 6,R1,R9 | go-request cannot be hand-posted / M20 | `inv_step` | blocking |
| RG-21 | 3,R1,R2 | registration token binds leaf and checkpoint / M21 | `processOne_inv` | blocking |
| RG-22 | 3,6,R1 | pause preserves checkpoint token / M22 | `inv_step` | blocking |

## Semantic atoms — Cage

| Atom | Ruling | Model site / mutation obligation | Owning theorem(s) | Severity |
|---|---|---|---|---|
| CG-01 | 5,#79 | `authorized.ownerKeyed` requires owner signature | `ownerKeyed_needs_owner`, `owner_bypass_breaks_inv` | blocking |
| CG-02 | 5,#79 | `authorized.ownerAndHook` requires owner signature | `ownerAndHook_needs_owner` | blocking |
| CG-03 | 5,#79 | `authorized.ownerAndHook` requires plugin withdrawal | `ownerAndHook_trivial_breaks_inv` | blocking |
| CG-04 | 1,5,#79 | `authorized.delegated` requires plugin withdrawal, not owner | `delegated_permissionless`, `delegated_is_registry` | blocking |
| CG-05 | 5,7,#102 | `runBody true` executes `pl.body` | `applyBatch_delegated_eq`, `delegated_is_registry` | blocking |
| CG-06 | 5,7,#102 | `runBody false` executes `cageOnlyBody` | `owner_bypass_breaks_inv` | blocking |
| CG-07 | 5,#101 | `routeValue.delegatedRouting` preserves plugin result | `applyBatch_delegated_eq`, `delegated_is_registry` | blocking |
| CG-08 | 5,#101 | `routeValue.refundAll` restores pre-body locked value | `refundAll_never_locks`, `refundAll_fold_locks_nothing` | blocking |
| CG-09 | 5,#101 | `routeValue.refundAll` returns exact bond to request owner | `refundAll_never_locks` | blocking |
| CG-10 | 5,#100 | delegated plugin pin is `mode = delegated → pl' = s.plugin` | `delegated_pins_plugin`, `owner_swaps_plugin`, `delegated_is_registry` | blocking |
| CG-11 | 5,7,#79,#101,#102 | delegated Cage/Registry execution correspondence | `applyBatch_delegated_eq`, `delegated_is_registry` | blocking |

## Semantic atoms — Samaritan

| Atom | Ruling | Model site / mutation obligation | Owning theorem(s) | Severity |
|---|---|---|---|---|
| SM-01 | 8,9,R11 | `Reap.hFund : Mr + tip ≤ Mc` | `reap_conserves`, `reaper_recovers`, `unprofitable_when_tip_too_high` | blocking |
| SM-02 | 8,9,R11 | `reap.intoRequest = Mr + tip` | `reap_conserves`, `fold_conserves` | blocking |
| SM-03 | 8,9,R11 | `reap.premium = Mc - Mr - tip` | `reap_conserves`, `reaper_recovers`, `samaritan_never_loses` | blocking |
| SM-04 | 9,R11 | `reap.reaperPays = fReap` | `samaritan_never_loses`, `self_folding_reaper_never_loses`, `unprofitable_when_tip_too_high` | blocking |
| SM-05 | 8,9,#101,#102 | `fold.toOwner = Mr` | `reaper_recovers`, `samaritan_never_loses`, `fold_conserves` | blocking |
| SM-06 | 8,11,#101 | `fold.toFolder = tip` | `self_folding_reaper_never_loses`, `fold_conserves` | blocking |

Semantic-atom denominator: **79 blocking, 0 advisory** (40 Checkpoint + 22
Registry + 11 Cage + 6 Samaritan).

## Theorem rows — Cage and Samaritan non-vacuity

The runner derives this inventory from compiled declarations and rejects drift.
Every row requires `witness=REACHED` and a relevant `kill=KILLED`; a shared
mutant may settle multiple rows, but the evidence remains per row.

| Row | Theorem | Required witness surface |
|---|---|---|
| TH-01 | `Cage.applyBatch_delegated_eq` | non-empty process and reject batches |
| TH-02 | `Cage.delegated_is_registry` | reachable delegated fold plus non-fold action |
| TH-03 | `Cage.delegated_permissionless` | same fold with owner signature false/true |
| TH-04 | `Cage.ownerAndHook_needs_owner` | owner false with hook both false/true |
| TH-05 | `Cage.ownerKeyed_needs_owner` | owner false with hook both false/true |
| TH-06 | `Cage.bypassed_breaks_inv` | concrete bypassed state violates active-checkpoint invariant |
| TH-07 | `Cage.owner_bypass_breaks_inv` | owner-keyed registration without plugin evidence |
| TH-08 | `Cage.ownerAndHook_trivial_breaks_inv` | shipped stub registration with hook |
| TH-09 | `Cage.owner_swaps_plugin` | owner-keyed fold changes plugin 7 to 8 |
| TH-10 | `Cage.delegated_pins_plugin` | delegated fold with unequal plugin |
| TH-11 | `Cage.refundAll_never_locks` | successful non-empty processed batch |
| TH-12 | `Cage.refundAll_fold_locks_nothing` | successful refundAll fold |
| TH-13 | `Samaritan.reap_conserves` | funded non-zero request/tip/premium |
| TH-14 | `Samaritan.reaper_recovers` | funded non-zero request/tip/premium |
| TH-15 | `Samaritan.samaritan_never_loses` | profitable stranger case with non-zero fee |
| TH-16 | `Samaritan.self_folding_reaper_never_loses` | profitable self-fold with both fees non-zero |
| TH-17 | `Samaritan.fold_conserves` | non-zero request and tip split |
| TH-18 | `Samaritan.unprofitable_when_tip_too_high` | funded but fee makes recovery unprofitable |

Theorem-row denominator: **18**. Structural failures (including broad
correspondence mirrors) are named once by the generated receipt and repeated on
each affected result; they never count as the owning semantic kill.
