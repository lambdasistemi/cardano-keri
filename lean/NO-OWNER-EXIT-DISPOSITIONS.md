# No owner exit: theorem and control dispositions

Issue #493. A checkpoint is alive until it is convicted: the owner close
(`Step.closePaid`, `Step.closeUnpaid`), the parked state, revival
(`Step.reopen`) and conviction from a parked state are removed from the
checkpoint machine, and `park`/`revive` with the parked carrier state from the
registry adapter. Conviction and its `terminationPending` completion are
unchanged.

Every theorem or definition whose statement was removed or changed is listed
here; none is deleted silently. A theorem not listed keeps its statement
unchanged (its proof may have lost the removed cases). The table was checked
against the repository's own theorem census
(`lean/retained-parking/story-bindings.mjs`): 40 statements left the census,
15 changed and 7 were added, and every one of them has a row below.

| Module | Declaration | Disposition | Reason |
| --- | --- | --- | --- |
| Checkpoint | `Intent.close, Action.close, Action.reopen (definitions)` | removed | the owner close and revival actions no longer exist |
| Checkpoint | `State.parked (definition)` | removed | the parked state no longer exists; State.sn?, consumableState, consumableStateB, State.leaf and State.hasOutput lose their parked arms |
| Checkpoint | `Step.closePaid, Step.closeUnpaid, Step.reopen, Step.convictParked (constructors)` | removed | stepFn loses the matching branches; T7_step_iff_stepFn still ties Step and stepFn |
| CheckpointCertificate | `reopenAllowed (executable helper)` | removed | the local certificate no longer needs the revival leaf guard; LocalEvent lost its revival clause |
| CheckpointGoals | `T8_parked_only_revives_or_convicts` | removed | the parked state no longer exists |
| CheckpointGoals | `T8_parked_returns_only_by_revival` | removed | the parked state and revival no longer exist |
| CheckpointGoals | `T1_reopen_strict` | removed | revival no longer exists |
| CheckpointGoals | `T1_close_rotation_cannot_revive` | removed | close and revival no longer exist |
| CheckpointGoals | `T2_close_and_reopen_open_epochs` | removed | close and revival no longer exist; T2_epoch_only_by_rotation is the surviving epoch statement |
| CheckpointGoals | `T4_current_key_thief_cannot_revive` | removed | the parked state and revival no longer exist |
| CheckpointGoals | `T5_convict_parked_enabled` | removed | conviction from a parked state no longer exists; T5_convict_enabled covers the only conviction |
| CheckpointGoals | `T5_close_enabled` | removed | the owner close no longer exists |
| CheckpointGoals | `T5_reopen_enabled` | removed | revival no longer exists |
| CheckpointGoals | `T10_reopen_is_juvenile` | removed | revival no longer exists; registration juvenility is unchanged in consumableState |
| CheckpointGoals | `T12_convict_parked_exact` | removed | conviction from a parked state no longer exists; T12_convict_exact is the only conviction inversion |
| CheckpointGoals | `T16_close_destination` | removed | the owner close no longer exists |
| CheckpointGoals | `T16_close_needs_rotation` | removed | the owner close no longer exists |
| CheckpointGoals | `T16_parked_hash_is_the_closed_checkpoints` | removed | the owner close and the parked state no longer exist |
| CheckpointGoals | `T16_copied_reap_refused` | removed | the owner close no longer exists, so there is no close message to copy |
| CheckpointGoals | `Step.convictParked_iff` | removed | the constructor is removed; the inversion-coverage command quantifies over the remaining constructors |
| CheckpointGoals | `Step.closePaid_iff` | removed | the constructor is removed |
| CheckpointGoals | `Step.closeUnpaid_iff` | removed | the constructor is removed |
| CheckpointGoals | `Step.reopen_iff` | removed | the constructor is removed |
| CheckpointLifecycleExamples | `Examples.parked_step` | removed | witness of the owner close; the close no longer exists |
| CheckpointLifecycleExamples | `Examples.revived_step` | removed | witness of revival; revival no longer exists |
| ConcreteConvictionGoals | `parked_convict_requires_concrete_pair` | removed | conviction from a parked state no longer exists; convict_requires_concrete_pair is unchanged |
| Registry | `Env.closeAuth, Env.rotationFrom (premises)` | removed | they guarded only park and revive; the wire environment table loses both columns |
| Registry | `CkState.parked, park, revive, Action.park, Action.revive (definitions)` | removed | parking and revival no longer exist in the registry adapter |
| RegistryAgreement | `Step.park, Step.revive (relation constructors)` | removed | the relation mirrors stepFn, which no longer has these actions |
| RegistryCustody | `park_retains` | removed | Registry.park no longer exists |
| RegistryCustody | `revive_retains` | removed | Registry.revive no longer exists |
| RegistryGoals | `park_iff` | removed | Registry.park no longer exists |
| RegistryGoals | `revive_iff` | removed | Registry.revive no longer exists |
| RegistryGoals | `pending_carrier_cannot_revive` | removed | revival no longer exists; a pending carrier has no local exit and a second conviction is refused by convictCkpt_iff |
| RegistryLifecycleExamples | `Examples.parking_success` | removed | Registry.park no longer exists |
| RegistryLifecycleExamples | `Examples.revival_success` | removed | Registry.revive no longer exists |
| RegistryLifecycleExamples | `Examples.parked_reachable` | removed | the parked state no longer exists; registered_reachable is the reachable source of conviction |
| RegistryLifecycleExamples | `Examples.W1_connected_parking` | removed | parking no longer exists |
| RegistryLifecycleExamples | `Examples.W2_connected_revival` | removed | revival no longer exists |
| RegistryLifecycleExamples | `Examples.W3_refused_revival_keeps_output` | removed | revival no longer exists |
| RegistryLifecycleExamples | `Examples.W4_wrong_recipient_and_missing_premise` | removed | the close premise and recipient no longer exist |
| RegistryReach | `refused_revival_keeps_carrier` | removed | revival no longer exists |
| CheckpointGoals | `T4_current_key_thief_cannot_park` | replaced by `T4_current_key_thief_cannot_rotate_or_freeze` | the conjunct "the successor is never parked" is dropped with the parked state; the other two conjuncts and all hypotheses are unchanged |
| CheckpointGoals | `T8_reopen_actor_is_proof` | replaced by `T8_freeze_and_convict_actors_are_proof` | the reopen conjunct is dropped with the action; the freeze and conviction conjuncts are unchanged |
| CheckpointGoals | `parked_and_convicted_hold_no_bonds_or_pool` | replaced by `convicted_holds_no_bonds_or_pool` | the three parked conjuncts go with the state; the three convicted conjuncts are unchanged; the pending equivalents are in pending_custody_observations |
| RegistryGoals | `parked_cannot_book` | replaced by `live_cannot_book` | the same refusal (keri-conviction-required) for the only unconvicted carrier state, live; new statement with its own story and reachable witness |
| RegistryLifecycleExamples | `Examples.parking_journey` | replaced by `Examples.registration_journey` | the same booked-and-folded registration journey without the park leg |
| Checkpoint | `poisonAfter (definition)` | changed | the reopen arm is removed |
| Checkpoint | `LocalEvent (definition)` | changed | the clause requiring an active leaf for a revival is removed with revival |
| CheckpointGoals | `local_progress_unless_pending_or_retired` | changed | the revival-premise hypothesis about parked states is dropped; conclusion unchanged |
| CheckpointGoals | `T6_dreg_enters_only_at_birth` | changed | the revival disjunct (reopen from parked) is dropped; registration from absent is the only birth; other conjuncts unchanged |
| CheckpointGoals | `T6_intent_requires_new_keys` | changed | the close-intent conjunct is dropped; deposit and keep-with-address conjuncts unchanged |
| CheckpointGoals | `T8_leaf_states` | changed | the parked disjunct of the active-leaf equivalence is dropped; active iff present or pending; retired clause unchanged |
| CheckpointGoals | `T8_mint_once` | changed | the reopen conjunct (revival requires a parked state and active key) is dropped; the registration conjunct is unchanged |
| CheckpointGoals | `T10_bonds_are_observable` | changed | the present-versus-parked conjunct now compares present with pending termination at the same hash parameter; the other two conjuncts are unchanged |
| CheckpointLifecycleExamples | `Examples.pending_step` | changed | conviction source is the rotated live checkpoint instead of the revived one; flow pool is 4 instead of 5 |
| CheckpointLifecycleExamples | `Examples.registry_convicted` | changed | the Registry conviction starts from the registered live carrier instead of the revived one |
| CheckpointLifecycleExamples | `Examples.stored_context_conviction_refused` | changed | the refused conviction is attempted from the registered live carrier instead of the revived one |
| ConsumerGoals | `retained_custody_refused (CI12)` | changed | the parked disjunct of the hypothesis goes with the state; the pending-termination refusal (proposition and Boolean) is unchanged |
| RegistryAuthorization | `ConvictionOrigin (definition)` | changed | the source carrier state of a recorded conviction is live only (parked is gone) |
| RegistryAuthorization | `pending_has_keri_authorization` | changed | the source-state disjunct (live or parked) becomes live only; every other clause unchanged |
| RegistryGoals | `convictCkpt_iff` | changed | the source-state disjunct (live or parked) becomes live only; every other clause unchanged |
| RegistryGoals | `local_actions_world` | changed | the local-action hypothesis shrinks to conviction only (park and revive are gone); conclusion unchanged |
| RegistryLifecycleExamples | `Examples.conviction_success` | changed | conviction from the registered live carrier instead of the parked one |
| RegistryLifecycleExamples | `Examples.W5_connected_termination` | changed | the connected termination starts from the registered live checkpoint (RegistrationJourney) instead of the parked one; every economic clause is unchanged |
| CheckpointLifecycleExamples | `Examples.rotated_step` | added | witness: the registered checkpoint rotates by its next keys (keep, paid premium); replaces the park/revive leg of the connected journey |
| RegistryLifecycleExamples | `Examples.W6_live_booking_refused` | added | reachable witness of live_cannot_book |
| CheckpointGoals | `T6_relayer_cannot_park_age_or_close` | unchanged | statement unchanged; proof loses the close cases; name kept as identity |
| CheckpointGoals | `trace_poison_fold` | unchanged | statement unchanged; proof loses the close, revival and parked-conviction cases; poisonAfter loses its reopen arm |
| RegistryCustody | `local_conviction_retains` | unchanged | statement unchanged; proof uses the narrowed local_actions_world hypothesis |
| RegistryCustody | `pending_record_frame` | unchanged | statement unchanged; proof loses the park and revive cases |
| RegistryGoals | `nonfold_frame` | unchanged | statement unchanged; proof loses the park and revive cases |
| RegistryGoals | `step_worldReachable` | unchanged | statement unchanged; proof loses the park and revive cases |
| RegistryReach | `wellFormed_step` | unchanged | statement unchanged; proof loses the park and revive cases |

## Model mutation controls

Mutants whose target code no longer exists are retired; every surviving
refusal theorem keeps at least one model mutant that a runtime check kills.
Fresh campaigns at this revision: Registry 13 of 13 killed, Checkpoint
retention 5 of 5, Checkpoint atoms 22 of 22, Samaritan 4 of 4; every
unmutated baseline passes.

Replacements: `pending-consumer-accepted` re-anchored to the pending branch
alone (owners `pending_consumer_refused`, `consumableStateB_iff`);
`pending-output-lost` (owner `T8_utxo_iff_active`) replaces
`parked-output-lost`; `conviction-pool-overpaid` (owners
`T6_component_conservation`, `T12_convict_exact`) replaces
`close-pool-overpaid`; atom CP-32 now retires a pending key, CP-35 makes
conviction touch the leaf, CP-38 gives pending termination a conviction bond,
CP-39 lets the current quorum rotate without next keys (owner
`T4_current_key_thief_cannot_rotate_or_freeze`) and CP-40 stops a rotation
from clearing the poison bit; `live-booking-allowed` now also owns
`live_cannot_book`.

| Manifest | Retired mutant | Former owner | Reason |
| --- | --- | --- | --- |
| checkpoint-atoms.json | CP-06 | `T12_convict_parked_exact`, `T5_convict_parked_enabled` | parked conviction without proof; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-07 | `T12_convict_parked_exact`, `T16_payments_are_named` | parked conviction invents bond; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-15 | `T1_reopen_strict`, `T5_reopen_enabled` | stale revival; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-16 | `T4_current_key_thief_cannot_revive`, `T5_reopen_enabled` | wrong retained key context; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-17 | `T2_close_and_reopen_open_epochs` | revival same epoch; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-18 | `T10_reopen_is_juvenile` | revival old age; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-19 | `T10_reopen_is_juvenile`, `T6_component_conservation` | revival frozen; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-20 | `T10_reopen_is_juvenile`, `T6_component_conservation` | revival no conviction bond; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-21 | `T16_close_destination`, `T2_close_and_reopen_open_epochs` | close old epoch; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-22 | `T16_parked_hash_is_the_closed_checkpoints` | close old sequence; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-23 | `T16_copied_reap_refused`, `T16_close_destination` | close copied payee; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-24 | `T16_copied_reap_refused`, `T6_intent_requires_new_keys` | close treated as keep; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-25 | `T16_close_destination`, `T16_copied_reap_refused` | close pays refund recipient as premium; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-26 | `T16_close_destination` | close ignores new refund recipient; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-27 | `T16_close_destination`, `T6_component_conservation` | close overpays pool; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-28 | `T16_close_needs_rotation`, `T4_current_key_thief_cannot_park` | close without rotation; its target (close, parked state or revival) is removed |
| checkpoint-atoms.json | CP-29 | `T5_close_enabled` | unpaid close disabled; its target (close, parked state or revival) is removed |
| checkpoint-mutants.json | parked-output-lost | `T8_utxo_iff_active` | its target (close, parked state or revival) is removed |
| checkpoint-mutants.json | parked-consumer-accepted | `consumableStateB_iff` | its target (close, parked state or revival) is removed |
| checkpoint-mutants.json | parked-pending-wrong-key | `T12_convict_parked_exact` | its target (close, parked state or revival) is removed |
| checkpoint-mutants.json | parked-premature-retirement | `T12_convict_parked_exact` | its target (close, parked state or revival) is removed |
| checkpoint-mutants.json | close-dreg-lost | `T16_close_destination` | its target (close, parked state or revival) is removed |
| checkpoint-mutants.json | close-bond-lost | `T16_close_destination` | its target (close, parked state or revival) is removed |
| checkpoint-mutants.json | close-pool-overpaid | `T6_component_conservation` | its target (close, parked state or revival) is removed |
| checkpoint-mutants.json | close-payee-changed | `T16_close_destination` | its target (close, parked state or revival) is removed |
| registry-mutants.json | park-token | `park_retains` | its target (close, parked state or revival) is removed |
| registry-mutants.json | park-min-ada | `park_retains` | its target (close, parked state or revival) is removed |
| registry-mutants.json | park-output | `park_retains` | its target (close, parked state or revival) is removed |
| registry-mutants.json | park-recipient | `park_retains` | its target (close, parked state or revival) is removed |
| registry-mutants.json | revive-wrong-key | `revive_iff` | its target (close, parked state or revival) is removed |
| registry-mutants.json | revive-no-fresh-bond | `revive_retains` | its target (close, parked state or revival) is removed |

## Simulator stories and traces

See `simulator/checkpoint-story-migration.json` and
`simulator/registry-story-migration.json` for the story dispositions.
