# Fixed refund address: theorem and control dispositions

Issue #505. The refund address belongs to whoever pays the registration and is
fixed for the checkpoint's whole life. A rotation no longer carries a new
refund address (`Action.rotate` loses its `refund'` argument), and the signed
rotation intent shrinks to the one thing the next keys still authorize: the
deposit that unfreezes the checkpoint. A relayer with public data alone still
lands a keep and nothing else (D-038). Conviction pays the freeze bond held and
the pool to the address the registration named.

Every theorem or definition whose statement was removed or changed is listed
here. A theorem not listed keeps its statement unchanged. The table was checked
against the repository's own theorem census
(`lean/retained-parking/story-bindings.mjs`): 2 statements left the census,
13 changed and 6 were added, and every one of them has a row below.

| Module | Declaration | Disposition | Reason |
| --- | --- | --- | --- |
| Checkpoint | `Intent, BondOp.intent, Env.intentOk (definitions)` | removed | the only signed rotation intent left is the deposit; a keep needs no signature |
| Checkpoint | `Env.intentAuthorized (premise)` | replaced by `Env.depositAuthorized` | the premise loses its intent and refund-address arguments: the keys of an epoch signed the deposit of the rotation that opens it |
| Checkpoint | `Env.bondOpOk (definition)` | added | the bond option's authorization: a keep always, a deposit when `depositAuthorized` holds |
| Checkpoint | `Action.rotate (constructor)` | changed | the `refund'` argument is removed |
| Checkpoint | `Live.rotated (definition)` | changed | the `refund'` argument is removed; `refundTo` is kept |
| Checkpoint | `Step.rotateKeepPaid, Step.rotateKeepUnpaid (constructors)` | changed | no refund argument and no authorization premise; the successor keeps `refundTo` |
| Checkpoint | `Step.rotateDepositPaid, Step.rotateDepositUnpaid (constructors)` | changed | no refund argument; the authorization premise is `depositAuthorized (l.epoch + 1)`; the successor keeps `refundTo` |
| Checkpoint | `stepFn (definition)` | changed | the rotation branch checks `bondOpOk` and keeps `refundTo`; T7_step_iff_stepFn still ties Step and stepFn |
| CheckpointTraceWire | `EnvTable.intentAuthorized (wire column)` | replaced by `EnvTable.depositAuthorized` | rows are `[epoch]`, as for the quorum |
| CheckpointGoals | `T6_refund_change_requires_new_keys` | replaced by `T6_refund_fixed` | the refund address no longer changes: no step between present states changes `refundTo` |
| CheckpointGoals | `T6_intent_requires_new_keys` | replaced by `T6_deposit_requires_new_keys` | the keep-with-address conjunct goes with the address; the deposit conjunct is unchanged except for the narrowed premise |
| CheckpointGoals | `T6_refund_fixed_along_trace` | added | along any trace between present states the refund address never changes |
| CheckpointGoals | `T6_refund_is_registration_address` | added | a trace from `absent` to a present state starts with the registration that named the held address |
| CheckpointGoals | `T6_conviction_refunds_registration_address` | added | conviction pays the freeze bond held and the pool to exactly the registration's address |
| CheckpointGoals | `step_from_present_keeps_refund` | added | helper: a step from a present state keeps the address or enters pending termination |
| CheckpointGoals | `T1_rotate_strict` | changed | the rotation binder loses `r'`; conclusion unchanged |
| CheckpointGoals | `T3_rotation_clears` | changed | the rotation binder loses `r'`; conclusion unchanged |
| CheckpointGoals | `T5_every_bond_option` | changed | quantifies over the bond option alone under `bondOpOk`; conclusion unchanged |
| CheckpointGoals | `T5_keep_is_rotated` | changed | `Live.rotated` and the rotation lose `r'`; conclusion otherwise unchanged |
| CheckpointGoals | `T5_deposit_on_full_is_keep` | changed | the refund conjunct becomes `l'.refundTo = l.refundTo`; the other conjuncts unchanged |
| CheckpointGoals | `T5_keep_needs_no_intent` | changed | the keep loses its `none` address argument; conclusion unchanged |
| CheckpointGoals | `T6_relayer_cannot_park_age_or_close` | changed | the hypothesis becomes "no deposit signed" and the conclusion "the step is a keep"; name kept as identity |
| CheckpointGoals | `T10_only_deposit_restores` | changed | the existential over the deposit action loses `r'`; other conjuncts unchanged |
| CheckpointGoals | `T15_b_returns_only_by_deposit` | changed | the existential over the deposit action loses `r'`; other conjuncts unchanged |
| CheckpointGoals | `Step.rotateKeepPaid_iff, Step.rotateKeepUnpaid_iff` | changed | no refund argument and no authorization conjunct |
| CheckpointGoals | `Step.rotateDepositPaid_iff, Step.rotateDepositUnpaid_iff` | changed | no refund argument; the authorization conjunct is `depositAuthorized (l.epoch + 1)` |

The exact types of the changed and added contracts moved from
`retained-parking/PreservedContracts.lean` (now 49) to
`retained-parking/ReviewedContracts.lean` (now 105).

## Model mutation controls

Fresh campaigns at this revision: Checkpoint atoms 22 of 22 killed, Checkpoint
retention 5 of 5, Registry 13 of 13, Samaritan 4 of 4; every unmutated
baseline passes. Atoms whose target text changed are re-anchored:

| Atom | Mutation | Owners |
| --- | --- | --- |
| CP-10 | the unpaid deposit resets `bornAt` | `T10_only_deposit_restores`, `T5_deposit_on_full_is_keep` |
| CP-12 | the deposit is checked as a keep | `T5_every_bond_option`, `T6_deposit_requires_new_keys` |
| CP-13 | a paid keep moves the refund address to the payee | `T6_refund_fixed`, `T5_keep_is_rotated`, `T5_keep_needs_no_intent` |
| CP-14 | `bondOpOk` lets an unsigned deposit through | `T6_deposit_requires_new_keys`, `T6_relayer_cannot_park_age_or_close` |
| CP-30 | `Live.rotated` resets `bornAt` | `T5_keep_is_rotated`, `T5_deposit_on_full_is_keep` |
| CP-39 | the current quorum rotates without next keys | `T4_current_key_thief_cannot_rotate_or_freeze` |

CP-13 formerly let a rotation move the address without the new keys'
signature; with no address to move, it now makes a rotation move it at all.

## Stories and scenarios

Story 8 ("Alice moves her refund address") wanted the money to come back to the
owner rather than to whoever registered the checkpoint; the decision reverses
that. The number is kept and the story is rewritten as the sponsor's: "The
refund address stays the sponsor's", played by
`simulator/checkpoint-simulator-scenarios/08-refund-stays-with-the-sponsor.json`.
A sponsor registers with refund address 6, Hal lands a keep, Alice lands a
signed deposit and tops up the pool, and Cora convicts: the conviction pays the
freeze bond and the whole pool, top-up included, to address 6.

Story 12 loses the clause "Mallory's bonds answer to Alice's keys": Alice's
later rotation lands and the refund address stays Mallory's. Story 4's deposit
guard is re-anchored on `depositAuthorized`. Every other scenario changes only
mechanically: rotations carry no address, deposit evidence rows are
`depositAuthorized: [epoch]`, the refusal is named `deposit-not-authorized`,
and the exhibited theorem rows follow the census above.
