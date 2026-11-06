# Request lifecycle: theorem and control dispositions

Issue #468. The redesigned Singular registry has no request script and no
reject or retract operation of its own; the KERI application decides how its
registration requests are spent. The decided lifecycle:

1. **Processing window: only the fold.** Until a request's deadline, only a
   valid fold that delivers the committed checkpoint may spend it. Nobody, the
   requester included, may cancel, reclaim or clean it up early.
2. **After the deadline, anyone returns it.** A request that was not folded
   (a duplicate key included) may be spent by anyone, with no signature, only
   by paying its refund address everything except the declared tip:
   `registrationCost + carrierAda`. The spender may keep the tip as its fee.
3. **The window is a deployment parameter**, `processTime`, counted from the
   booking transaction's validity upper bound (`submittedAt`, which booking
   requires to equal that bound): `deadline = submittedAt + processTime`.
4. **Conviction custody is unchanged.** The pending-termination output is not
   a registration request; only the registry's terminating fold consumes it.

Decisions 1 and 2 together require the KERI registry's Singular configuration
to have `retractTime = 0`: the imported expiry ground opens at
`submittedAt + processTime + retractTime`, so a positive `retractTime` would
leave a valid unfolded request with no spending path after the deadline. The
model names this `Deployment`; the scenario fixtures use it.

`Action.genericRetraction` and `Action.genericRejection` are replaced by one
action, `Action.returnRequests`, whose transition `returnRequests` refines the
imported rejection with three guards: every member names a booked
registration, the transaction's whole validity interval starts at or after
each member's deadline, and the transaction balances.

Every theorem whose statement was removed or added is listed here. A theorem
not listed keeps its statement text; theorems that quantify over `Action`
(for example `step_iff`, `wellFormed_step`, `nonfold_frame`) now cover the new
action set. The table was checked against the repository's theorem census
(`lean/retained-parking/story-bindings.mjs`): 6 statements left the census,
none changed, 19 were added, and one narrative changed.

| Declaration | Disposition | Reason |
| --- | --- | --- |
| `genericRetraction` (definition, action) | removed | no owner retraction window: until the deadline only a fold spends the request |
| `genericRejection` (definition, action) | replaced by `returnRequests` | the imported rejection is kept as the judgment, refined by the deadline, registration-only and balance guards |
| `generic_retraction_sound` | removed | its action is gone |
| `generic_rejection_sound` | replaced by `return_sound` | also states the three KERI guards |
| `retraction_refund_and_guards` | removed | its action is gone |
| `rejection_refund_destinations` | replaced by `return_refund_floor` | same floor, over the return |
| `termination_retraction_refused` | removed | its action is gone |
| `termination_rejection_refused` | replaced by `termination_return_refused` | same refusal, over the return |
| `registered_registration_refused` | narrative only | now names the deadline and the return as the duplicate's only exit |
| `deadline`, `Deployment`, `returnedRegistration`, `returnMemberReady` (definitions) | added | the decided window and the return's member checks |
| `fold_ends_by_deadline` | added | a fold selecting a registration ends by its deadline |
| `return_starts_at_deadline` | added | a return starts at or after each member's deadline |
| `consumed_registration_spends` | added | a step spending a booked registration is a fold within the window or a return after it |
| `window_spend_is_fold` | added | before the deadline nothing but a fold spends the request |
| `return_pays_refund_address` | added | each returned request's refund address receives at least its contents less its tip |
| `duplicate_returned_after_deadline` | added | a duplicate key's request is spent only by a return from its deadline |
| `termination_custody_only_fold` | added | a pending termination leaves custody only through its fold |
| `return_interval_present`, `return_member_is_registration` | added | construction facts: the imported missing-interval, termination and not-pending refusals are never the return's answer |
| `guard_holds`, `registration_find_unique`, `registration_refs_unique`, `foldPrerequisite_window`, `consumed_registration_selected`, `return_registrations`, `le_sum_of_mem` | added | helper lemmas of the above |

## Controls

| Control | Disposition |
| --- | --- |
| Boundary rows `retract-*` (20) | removed with the retraction |
| Boundary rows `reject-*` | replaced by `return-*`, each balanced so the intended refusal is the one observed; added before, straddling and at the deadline, a signer present, unbalanced, a reduced refund, a redirected refund, an extra input and a registry deployed with a retraction window |
| Trace `registration-retraction` | replaced by `registration-window`: a fold ending at the deadline, a fold after it, a return inside the window and a return at the deadline |
| Registry stories 4, 5, 6, 14, 15 | rewritten; see `simulator/registry-story-migration.json` |
| Registry model mutants | 6 added for the deadline, the window, the balance and the registration-only guard, killed by `RegistryReturnChecks` |

## Limits

`return_pays_refund_address` and `return_refund_floor` state the refund floor.
That the spender keeps at most the declared tips follows from the balance
guard, the imported rule that the inputs are exactly the members, and the
imported observation that each request output holds its recorded contents; it
is checked on every row of `request-lifecycle-vectors.json` but is not stated as
a separate theorem. Liveness of the return (that some return transaction is
accepted for every unfolded request after its deadline) is exhibited by the
vectors and drivers, not proved universally.
