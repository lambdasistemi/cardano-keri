# The inception at the booking: theorem and control dispositions

Issue #559. The registration design says KERI validates a registration before
it mints the approval. The model validated at the fold: the spend of a request
by a fold required the key's inception evidence and checked that the delivered
datum was the initial checkpoint state. The decided placement:

1. **The booking validates.** The application mints a registration approval
   only for a key that has its inception evidence and for a request whose
   initial datum is exactly the initial state of the key.
2. **The fold delivers.** The spend of a request by a fold reads no evidence
   and validates no datum: it delivers the committed address, the committed
   datum, exactly the deposit and the one new active token.
3. **A folder needs nothing from the controller.** The address, the datum and
   the deposit are the request's data. The fold is the one the upstream client
   builds (`SingularApplicationHeld.buildFold`); KERI's adapter adds the
   registry's configuration record, read by reference, and the treasury
   donation.
4. **The request's `initialDatum` is the datum itself**, as in the upstream
   model, whose client copies the field into the holding. The earlier revision
   read the field as the datum's hash, so the holding the upstream client
   builds was refused. That an approval's name commits the datum by its hash
   is the byte encoding of the approval preimage; the approval bytes of the
   vectors are unchanged.

The economic registry moves the same guard: `Registry.bookRegistration`
refuses a key without evidence and `Registry.fold` takes no evidence.

## Theorems

| Theorem on the earlier revision | Disposition | Now |
| --- | --- | --- |
| `Registry.fold_iff`, `fold_sound` | restated | the authorization clause is gone; `folded_registration_has_inception` proves it of a reachable registry |
| `Registry.fold_complete` | restated | no evidence hypothesis: a reachable registry and upstream acceptance suffice |
| `Registry.bookRegistration_sound` | restated | adds that the key has its evidence |
| `Application.registration_spend_is_fold_or_return` | restated | the evidence clause is gone; the delivery is of what the approval commits |
| `Application.booking_inversion` | restated | adds the evidence and that the initial datum is the initial state |
| `Application.fold_refuses_other_state` | replaced | `booking_refuses_other_state` |
| `Application.fold_refuses_other_aid` | replaced | `booking_refuses_other_aid` |
| `Application.fold_refuses_pool_below_premium` | replaced | `booking_refuses_pool_below_premium` |
| `Application.fold_refuses_unrecorded_refund` | replaced | `booking_refuses_unrecorded_refund` |
| `Application.delivered_credential`, `fold_spend_delivers`, `fold_refuses_inexact_holding`, `before_deadline_only_fold` | restated | `delivered` no longer takes the configuration record or the parameters |
| `Application.fold_delivers_to_checkpoint_validator`, `delivered_initial_state`, `fold_delivers_initial_state`, `delivered_is_genuine`, `before_deadline_delivers_genuine` | restated | each takes the accepted booking as a premise; the configuration record named is the one the booking read |
| `Application.genuine_holds_committed_datum`, `genuine_checkpoint_consumable_iff` | restated | the request commits the datum itself, so no collision-freedom premise; the consumer theorem asks only that the two interpretations agree on the active token |
| every other `Registry` theorem naming `fold` or `bookRegistration` | restated | the evidence environment leaves the fold's arguments and enters the booking's |

New: `Registry.booking_refuses_missing_inception`,
`booked_request_has_inception`, `registered_key_has_inception`,
`folded_registration_has_inception`, `only_booking_reads_inception`;
`Application.booking_refuses_missing_inception`,
`accepted_booking_has_inception`, `registration_approval_requires_inception`,
`only_booking_reads_inception`, `booking_initial_state`,
`booked_initial_state`, `fold_delivers_committed`,
`fold_refuses_other_datum`, `fold_refuses_other_address`,
`delivered_holds_committed`, `delivered_writes_initial_state`,
`single_fold_accepted`, `public_fold_accepted`, `fold_refuses_unread_record`.

## Behaviour that changed beside the placement

A request whose deposit cannot pay one premium, or whose refund address no
checkpoint can record, was booked and could only be returned after its
deadline. It is now refused when booked.

## Controls

| Control on the earlier revision | Disposition | Now |
| --- | --- | --- |
| `registry-mutants.json` `registration-no-inception` (the fold's guard) | retargeted | the booking's guard; killed by the retention check's refused booking |
| `application-mutants.json` `fold-checkpoint-validator` | retired | the fold no longer compares the holding with the configuration record; `booking-holding-address` covers the address |
| `application-mutants.json` `fold-initial-state-unchecked` and the eleven `fold-initial-…` cases | retargeted | the same mutations of the same definitions, killed by booking rows (`booking-initial-…`) |
| new | added | `booking-inception-unchecked`, `fold-reads-inception` (both ledgers), `booking-evidence-of-another-field` (registry) |

The evidence read again at the fold is a mutant of the dispatch, where the
environment is still in scope: `fold-reads-inception` in both ledgers guards
the spend of a request (application) and the fold step (registry) with the
evidence again. They are killed by the vector row
`fold-without-inception-evidence` and by the retention control
`fold-reads-no-inception`. Inside `spendRegistration` and `Registry.fold` the
same mutation does not compile, because neither takes an environment.

The invariant that every pending request has its evidence has its own control,
`pending-requests-have-evidence`: under an environment where a request's
refund address has evidence and its key has none, whatever the booking step
leaves pending must be of a key with evidence. The registry mutant
`booking-evidence-of-another-field` keeps a guard at the booking but reads the
evidence of the refund address; the single refused booking does not see it,
and that control kills it. No step other than the booking adds a pending
request, so there is no second place to corrupt the pool from.

The fold the upstream client builds is in the vectors twice. As the client
builds it, it donates nothing: the public registry accepts it
(`clientFold.asBuilt`) and KERI's application refuses it for the missing
donation (row `fold-built-by-singular-client-no-donation`). With the donation
taken out of the folder's own output it is one balanced transaction that the
public registry accepts (`clientFold.withTheDonation`) and KERI's application
accepts (row `fold-built-by-singular-client`). Neither judgement reads the
balance. Without the configuration record the application refuses it.

A KERI fold keeps three things the upstream client's fold does not have: the
configuration record read by reference, the treasury donation of the
registration cost, and the application's redeemer that names the request it
folds and its new holding. They are the work of KERI's adapter, which computes all three from the
chain; the folder supplies nothing. A fold without any one of them is refused
(rows `fold-built-by-singular-client-no-record`,
`fold-built-by-singular-client-no-donation`, `fold-with-unnamed-request`).

## Limits

The evidence is an opaque fact of the key. The model states neither the
signatures and receipts of an inception nor that the key material written in
the initial datum is the inception's; the validator must check both.
