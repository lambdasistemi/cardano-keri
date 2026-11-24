# Verify retained custody and associated retirement

The current campaigns execute the actual model definitions and complete finite
fixtures. Each subject must compile against an unchanged baseline and its
mutant before execution. Only its bound runtime assertion counts as a kill.
A proof failure, missing import, timeout or unrelated error is not a kill.

| Campaign | Cases | Evidence |
| --- | --- | --- |
| `checkpoint-atoms.json` | 52 | Local decidable mirror and observation mutations, including the commitment a conviction reveals (the key state, evidence, payee and window it names, its one-slot age, that a top-up, a freeze and a poison keep it, its burn, and that it is open for this AID and this deployment); complete result checks |
| `checkpoint-mutants.json` | 5 | Pending refusal, pending keys and addressed conviction flows |
| `registry-mutants.json` | 21 | Token/output/minimum ADA, live-booking refusal, custody tails, binding domain, generation and plugin; the return's deadline, balance and registration-only guards |
| `samaritan-mutants.json` | 4 | Actual constructor domain, request funding, premium and external fee |
| `application-mutants.json` | 55 | KERI's application on the application-held model: foreign registry, retraction window, carrier floor, exact request contents, holding address committed to the checkpoint validator, checkpoint validator distinct from the application, deadline, configuration reference, one approval, the inception evidence at the booking, that the initial datum the request carries is the initial checkpoint state (each of sequence number, epoch, poison, freeze, top-up, birth slot and refund address, a pending termination, the AID, one premium in the pool, a refund address a checkpoint can record), fold deadline, holding at the committed address, exact holding, the delivered datum, the closed application mint (unchecked, and each justified configuration token, approval, burn and termination burn dropped), treasury donation, approval burn, return deadline, refund amount and address, active burn, uncovered inputs; the termination booking (the pending datum, its key, the checkpoint validator's address, the minimum ADA, the active token held, the request's shape and exact lovelace each way, the registry's state policy, one approval per booking, the justified approval), the terminating fold's configuration reference and treasury donation, and the checkpoint validator's release (pending datum, one approval) |
| `reader-status-mutants.json` | 56 | The reader's status: the authenticated context, a holder deciding beside a history that refuses it (complete or not), a history that refutes itself whatever it names, the members an incomplete history is replayed from (the creation, a key not taken as active, a termination or a registration not accounted for), the point and the asset of the holding observation, the point, the registry and the completeness of the history (for the leaf, and for refusing a holder), the replay (a registration of a key the registry already knows, a termination of a key that is not active, a fold without a change), the holder's credential, quantity and identifier, the convicted checkpoint and the termination request, two holders, every cell of the table of custody, history and leaf (each deciding cell changed, and each refusing cell given a status: a missing token, no evidence, a holder against the history, a registered key without its holder, an inconsistent holding), and the holder the answer names |

The application campaign rebuilds `Application.lean` and its vectors from the
mutated source and requires each committed row of `lean/application-vectors.json`
to keep its verdict; a mutant is killed only by the row it is bound to. The
reader's status campaign does the same with `ReaderStatus.lean`, its vectors
and `lean/reader-status-vectors.json`: each committed row's own evidence must
keep its committed answer.

The economic campaign compiles the exact definition prefix of `Samaritan.lean`
without its proof suffix. It tests definitions, not whether a modified proof
script happens to elaborate. The full unmodified module is built and audited
separately. Whole-pending tail mutations are detected by reconstruction refusal;
they demonstrate lost valid execution, not acceptance of a malformed successor.

Run each with the project compiler and a fresh, nonexistent receipt directory:

```sh
node lean/retained-parking/run-registry-mutants.mjs RECEIPTS Registry
node lean/retained-parking/run-registry-mutants.mjs RECEIPTS Checkpoint
node lean/retained-parking/run-registry-mutants.mjs RECEIPTS Checkpoint checkpoint-atoms.json
node lean/retained-parking/run-registry-mutants.mjs RECEIPTS Samaritan
node lean/retained-parking/run-registry-mutants.mjs RECEIPTS Application
node lean/retained-parking/run-registry-mutants.mjs RECEIPTS ReaderStatus
```

Set `LEAN_BIN` to the project's pinned compiler if it is not on PATH. Each run
records exact sources, commands, model/subject compilation, exits and bound
failures. Finite mutation coverage does not prove that no other fault survives.

The two `run-system-implementation-mutants.mjs` cases alter the JavaScript
certificate adapter: consuming another request and replacing the stored context.
They are implementation mutants. The separate foreign-context receipt controls
are type-interface checks. Neither category is counted as a Lean model mutant.

`ReviewedContracts.lean` checks all 151 revised exact contracts and
`PreservedContracts.lean` checks 49 preserved contracts. `theorem-stories.json`
binds 676 lifecycle, transport and application theorem identities, their source narratives,
complete formal Given/Then and source hashes. `story-bindings.mjs` rejects drift;
compilation remains the authority on the propositions and axiom closure.

The earlier mutation ledgers and receipts remain historical at their recorded
revisions. In particular, their 79-atom/20-theorem denominator is not a fresh
result for this revision. The owner-exit removal retired the parking, revival
and close mutants (31 of them, listed with reasons in
`../NO-OWNER-EXIT-DISPOSITIONS.md`); the old system-revival guard has no
current counterpart; exact stored-origin
and pending-request completion have separate actual-system evidence.

Production validators and builders require their own two implementation layers
and independent acceptance. These model and simulator checks do not supply it.
