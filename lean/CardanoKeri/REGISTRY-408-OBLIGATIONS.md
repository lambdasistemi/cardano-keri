# #408 obligations: what is proved, what is stated, what is owed

Ruling 12 (D-039/D-040) removed pause, resume, the on-chain parked state and
the grace window. The checkpoint machine adopted it on 2026-09-04 through #359.
This records the registry machine's adoption, and everything the adoption does
**not** discharge.

## Proved

Verified with `CollectAxioms`; none depends on `sorryAx`.

| theorem | says | axioms |
|---|---|---|
| `parked_leaf_no_ckpt` | a parked leaf implies no checkpoint, and the projection reads the reached key state off the leaf | `propext`, `Quot.sound` |
| `custody_of_pending` | the closing key state rides in a real inbox entry | `propext` |
| `W1_reach` | the close story is reached, by derivation from `Reach.init` | none |
| `W3_key_still_pending` | a revive attempt cannot lose the pending key state | none |
| `W4_wrong_recipient_refused` | a reap to an address the premise does not name is refused | none |
| `W5_tomb_leaf` | conviction tombstones; the tombstone reap and its fold land the convicted leaf | none |

Both libraries build clean: 26 jobs, no errors, no `sorry` warnings.

## The undischarged premise, and what may never be proved against it

`env.closeAuth aid recipient` is the plainly named, **undischarged** abstract
close-authorization premise. It supplies the opaque address the live bond
returns to. Every theorem takes it as a **hypothesis**; it is never assumed
globally.

**Owner: #358.** Its job is to discharge this premise with the
witnessed-rotation and D-038 signed-intent checks.

**What #408 may prove:** value conservation — the bond leaves the checkpoint,
arrives at the abstract recipient, the accounting balances.

**What #408 may not prove, and has not:** that the recipient is the owner, or
that the reaper cannot be the recipient. Those are #358's guarantees. Proving
them against an undischarged premise makes them **vacuous** — worse than
absent, because they read as settled.

**Why `env.quorum` was refused as the intermediate authorization:** #358's own
issue body proposes live reap via `env.quorum` as a structural precursor and
then **explicitly replaces it**, because current-key theft and copied-payee
attacks survive it. It is *known-wrong* authorization, not an unexamined
default. A precursor its own ticket has rejected must never be silently
promoted by a lane that only reads it written down.

## The observation boundary

Agreement with the checkpoint machine is judged at a **projection**, never
step-by-step. The registry is an MPFS instance and its request/fold transport
*is* the modelled thing; `Checkpoint.lean` explicitly excludes request
mechanics. The two machines model different **layers**.

A close is two raw steps — the authorized reap, then the fold — and `project`
names the transit state between them. Forcing `active-iff-checkpoint` at every
raw step would replace the registry's semantics with the checkpoint machine's
and call the result agreement. `Inv.activeCkpt`'s "checkpoint **or** pending
go-request" stays: it is the transport being honest about itself.

## Owed, with owners

| # | obligation | owner | note |
|---|---|---|---|
| 1 | five registry scenario fixtures still contain `pause`/`resume` | #408, simulator half | see below |
| 2 | proposed semantic-mutant rows, and their falsification | #408 | proposals below |
| 3 | freeze **and falsify** the gate against the actual interface | #408 | a gate that has never failed detects nothing |
| 4 | independent completeness and inversion inspection | fresh seat | never the author |
| 5 | discharge `env.closeAuth` | #358 | downstream |
| 6 | registry integration | #324 | follows #358 |
| 7 | `Cage.lean` consolidation against Singular | undecided | see below |

### 1. The simulator fixtures

`09-pause-and-resume.json`, `10-sam-reaps.json`, `11-alice-revives.json`,
`13-convict-dormant.json`, `14-go-request-cannot-be-bricked.json`.

These encode the retired lifecycle as **expected behaviour** — one has a pause
succeeding, then a reap refused *"inside the grace window"*, then succeeding
after it. Repairing them rewrites what the stories demonstrate; it is not line
deletion. `09-pause-and-resume.json` covers a retired feature end to end.

The scenario extent guard pins `registryFiles: 15`, so removing a scenario
must move that pin. That guard is working correctly and must not be weakened to
make this pass.

Until this lands, `RegistryTraceDriver.lean`'s story fold fails `unknown
action`. That failure is now downstream of the model, not a defect in it.

### 2. Proposed semantic mutants

Each must turn the gate RED, and each must be shown to do so:

- admit a live reap whose recipient the premise does not name → `W4` must fail
- let the fold land a conviction without the tombstone reap → `W5` must fail
- drop the go-request on a revive attempt → `W3` must fail
- let a dormant leaf coexist with a checkpoint → `parked_leaf_no_ckpt` must fail
- weaken `pendingGo` to ignore `userPostable` → `custody_of_pending` must fail
- restore a grace-window branch to `reapable` → the ruling-12 removal must fail

A mutant that only breaks elaboration establishes nothing. Each needs a compile
witness so a wrong-reason RED is caught.

### 7. `Cage.lean` and Singular

`Cage.lean` (344 lines) models the upstream cage the keri registry plugs into.
The operator has settled that **Singular is that registry**. Singular's Lean
was measured on 2026-09-14: it builds clean on our pinned 4.27 toolchain
(exit 0, 16 jobs), has **no external dependencies — not even mathlib**, and
carries **500 theorems in its namespace, none depending on `sorryAx`**.

So we maintain our own model of a machine that is better specified elsewhere.
What remains undecided is only *how* to import — a build dependency or
vendoring — which is a coupling decision, not a design one.

## Three fixtures were wrong, not three claims false

Recorded because the distinction cost real time. `W4` named the environment
whose premise **admits** recipient 4 while asserting a reap to 4 is refused —
one token. `W3` and `W5` each observed a state their trace had already run
past. The earlier seat was right that a failed `rfl` establishes neither truth
nor falsity; what settled it was **evaluating** the terms rather than trying to
prove them.
