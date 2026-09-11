# Contract registry — cardano-keri M1

Re-cut 2026-09-04 for plan v2. The pre-reopening registry (founding sweep
2026-07-29, V1 preprod / `ckeri deploy` / MPF-key era) is superseded: plan v2
deletes the enforcement economy and the M1.2 skeleton, so most of its parties
no longer exist. Entries below are this seat's, and an entry is a claim until
its `enforced:` line names a check someone has seen fail.

A contract with no enforcing check is the architectural form of a check that
cannot fail. Every `NONE` here is a scheduled incident with a named owner.

---

contract:   script-size-ceiling — the compiled validator must fit a transaction
parties:    cardano-keri onchain (produces UPLC), the Cardano ledger (consumes)
invariant:  every shipped validator, after parameter application, fits inside
            16,384 bytes, and the transactions carrying them fit too
enforced:   **NONE.** Measured once, 2026-08-18: `checkpoint.checkpoint` at
            25,934 bytes = 158.3 % of the limit; three others at 80–92 % before
            parameters. This single measurement is the whole reason the prior
            M1 line was ruled NO-GO. Commissioned: **#336**, the size table of
            the surviving scripts after K1's deletion.
caveat:     byte length under 16,384 does not prove a transaction fits. A size
            table that reports only script bytes discharges half this contract.

contract:   lean-is-the-specification — the Lean machine and the on-chain code
parties:    `lean/` checkpoint + registry machines (specify), Aiken validators
            and `ckeri` (implement)
invariant:  the shipped validators admit exactly the transitions the Lean
            admits, and refuse exactly what it refuses
enforced:   PARTIAL and forward-looking. #343 commissions the consumer
            predicate checked against the Lean's decidable mirror; nothing
            checks the rest yet. Known gap recorded in `LEAN-CLARITY.md`:
            `consumableState` is a `Prop` with no `Decidable` or Bool mirror,
            so its executable twins are unproved against it.
owner:      K4 #322 / K6 #324 tickets; epic #367 closes the Lean side first.

contract:   lean-simulator-fidelity — the simulator follows the stated Lean
parties:    `lean/` (specifies), `docs/simulator/` pages (portray)
invariant:  every simulator transition and refusal is the Lean's, and the
            published page is the audited one
enforced:   WEAK — scenario gate, trace gate, vacuity pass, template check, all
            exit 0 today. Weakened by the denominator defect below: an empty
            run is green. Two residuals: rows deduplicated by story-clause text
            (two atoms from one phrase share an identity, deleting either stays
            green), and `lean/mutants/run.sh` printing `TOTAL 0/0`.
owner:      **#362** across all five gates, with a control each.

contract:   gate-denominators — a gate that counts problems must not pass on
            an empty extent
parties:    every gate in the tree (asserts), every acceptance above it (relies)
invariant:  a quantifier that ranges over an empty or truncated set fails,
            and that guard is itself falsified
enforced:   NONE. Filed as **#362**; folded into the shared `lean-simulations`
            skill. This is the cross-cutting invariant shape of the milestone —
            it devalues every other lane's evidence until it lands.

contract:   mpfs-registry-interface — one incarnation per identity
parties:    cardano-foundation/cardano-mpfs-onchain (produces: permissionless
            batching #98, gating plugin #99, leaf-map interface #104),
            cardano-keri K6 #324 (consumes)
invariant:  the keri registry integration is built against the MPFS surface
            that is actually merged upstream, not against the design of it
enforced:   NONE. Tracked by #329 / #330; upstream issues carry a "consumed by
            cardano-keri M1" line. Both sides are in the operator's lane, and
            the upstream repos are under cardano-foundation — so drift here
            cannot be arbitrated inside this milestone.
open:       where the MPFS modification lives (keri-specific cage vs upstream
            permissionless mode) is undecided; the answer changes which side of
            this contract moves.

contract:   keripy-parity — ckeri consumes real WebOfTrust artifacts
parties:    WebOfTrust keripy `kli` (produces KEL events, receipts, OOBIs),
            cardano-keri (consumes and verifies)
invariant:  advance verification accepts exactly what keripy accepts; we never
            wrap or fork kli UX
enforced:   COMMISSIONED, not yet built — **#337**, the advance-versus-keripy
            parity oracle with a mutant that flips the witness set. Until it
            exists this is NONE.
note:       projection only. The design may rely on nothing GLEIF/QVIs do not
            already publish; no fresh signature may be requested from a KERI
            party.

contract:   verification-cost-at-GLEIF-scale
parties:    cardano-keri advance validator (spends budget), the Cardano
            execution-unit limits (bound it)
invariant:  a real GLEIF-shaped advance fits the per-transaction budget
invariant:  measured cost is re-derived on the slimmed tree, not inherited
enforced:   NONE. Prior measurement: memory breach at 24 keys, ~7-key practical
            ceiling at premint, depth not the cost driver — all under the
            caveats in `ledger.md` (frontier not reached, depth extrapolated).
            Commissioned: **#338**, cost by witness count and signer count.
            Known problem: a GLEIF 24M-memory advance is real, and the
            redesign direction is extending premint proofs to Ed25519
            signatures and receipts.

contract:   preprod-deployment-manifest
parties:    the publisher (produces script hashes and addresses), producers and
            watchers (pin and consume)
invariant:  deployed scripts match the repo's verifiable release manifest
enforced:   NONE at present. `ckeri manifest verify` exists (#158) but nothing
            was ever shown to run it automatically; the prior registry marked
            it TODO-AUDIT and it was never audited. Re-lands under K10 #356.
            Treat as NONE until a CI or gate invocation is observed failing.

---

## Registry hygiene

Nothing above is `enforced:` on the strength of a source-text grep. Where a
line says a check exists, it names the ticket that builds it rather than
claiming it runs. The four `NONE` entries with commissioned tickets are #336,
#362, #337, #338; the two `NONE` entries without an owner in this milestone are
`mpfs-registry-interface` (operator's lane, cross-org) and
`preprod-deployment-manifest` (K10, unopened).

---

contract:   scenario-grammar — one grammar, two interpreters
parties:    #375 (produces the DSL grammar/parser), #376 devnet runner
            (consumes it)
invariant:  no forked parsers. A grammar change in #375 must **break #376's
            build**, never silently diverge.
enforced:   NONE. It is asserted in #375's Interface section and in #376's
            first acceptance criterion — two issue bodies agreeing with each
            other, which is not a check. Owned by epic #326; its owner is
            instructed to escalate here the moment a child proposes to satisfy
            it by agreement rather than by a build that breaks.
note:       this contract is the reason #375 is ordered before #374 and #376.

contract:   dsl-json-equivalence — the DSL compiles to the gate input with no
            semantic loss
parties:    #375 (compiles DSL -> JSON), the existing scenario/trace gates
            (consume JSON)
invariant:  DSL->JSON round-trips all 30 existing scenarios with no
            `expect`/`flow`/`exhibits` silently dropped, and malformed DSL
            fails closed with file:line rather than a silent partial story
enforced:   NONE yet — commissioned inside #375's acceptance criteria.
caveat:     **green gates do not currently discharge this.** While #362 is
            open an empty run is GREEN across all five gates, and scenario
            rows are deduplicated by story-clause text. A DSL that keeps the
            gates green has therefore proved less than it appears to. Written
            into the #326 brief.

---

contract:   conviction-matches-keri-duplicity — the conviction predicate and
            the KERI 1.1 duplicity, first-seen and superseding rules
parties:    `convict_predicate` in `onchain/.../checkpoint/enforcement.ak` and
            `Checkpoint.lean`'s `duplicityAt` (implement); KERI 1.1 at
            `kswg-keri-specification@fbdd4a6` (specifies)
invariant:  a conviction is accepted exactly for two non-delegated rotations at
            one sequence that KERI would call irreconcilable duplicity: each
            signed by a satisfiable subset of the prior-next list, each
            receipted against its own resulting witness set at its own
            threshold; never for a delegated identity, never for an
            interaction conflict, never by rolling the tip back
enforced:   **NONE.** The 11 September watcher conformance review is evidence
            only: 31 Aiken tests plus one mutant, eight checkpoint probes,
            twelve rapid-rotation probes, a quorum enumeration. The shipped
            predicate is known to diverge in two ways (exact-key match instead
            of prior-next subsets; receipts graded against the tip's set) and
            to leave a zero-block window against a thief who rotates twice in
            one block. Owner: the Lean invariants plan epic (story S-30), the
            challenge-alternatives slice; its ruled shape then re-cuts #347.
caveat:     KERI's location is the sequence number; the prior-digest check is
            a narrower sibling test, not a conformance requirement. The
            cool-down is an application timing policy standing in for the
            spec's propagation-time boundary, and needs a separate expiry rule
            for a tip that never moves.

contract:   ruling-12-on-both-machines — an adopted lifecycle ruling holds in
            every model that implements the lifecycle
parties:    `lean/CardanoKeri/Checkpoint.lean` (adopted ruling 12 / D-039 /
            D-040 via #359, closed 2026-09-04),
            `lean/CardanoKeri/Registry.lean` (has not — still carries `parked`,
            the grace window, `stepFn_pause_iff`, `stepFn_resume_iff` and the
            `env.quorum` reap authorization)
invariant:  no model admits a transition an adopted ruling removed, and no two
            model headers disagree about whether a clarity question is answered
            (`Checkpoint.lean` says D-039 answers Q-R6;
            `REGISTRY-LEAN-CLARITY.md` still lists Q-R1 and Q-R6 open)
enforced:   NONE. Found by hand during #318 on 2026-09-11, after the ruling had
            been half-applied since 2026-09-04. **The registry-side slice was
            never filed** — #316 (the registry model) is CLOSED and #358 is
            blocked on an artifact with no issue number. The #318 epic owner is
            authorized to file it; this desk owns finding it an implementer.
shape:      this is the milestone's per-path re-land defect: a ruling carried
            path-by-path can miss a path forever, and the closed parent makes
            the unfinished half invisible. It is the second time this shape has
            cost this milestone real work.
owner:      the new registry-slice-3 issue, upstream of #358 and #324.

---

## 2026-09-11 correction — three entries above overstated their enforcement

`lean-simulator-fidelity` says the scenario gate, trace gate, vacuity pass and
template check "all exit 0 today". `scenario-grammar` and
`dsl-json-equivalence` name checks inside #375 and #376. All three readings are
wrong in the same way, and this desk found it by auditing the `NONE` list
rather than by any lane reporting it.

**The three simulator gates are invoked by nothing.** The string `simulator`
does not appear in `justfile` or anywhere under `.github/workflows/`. The only
references to `scenario-dsl-gate` in the tree are its own source,
`simulator/README.md` and `specs/375-scenario-dsl/plan.md`. They run when a
person runs them and at no other time. Filed as **#424**.

So every "exit 0 today" in those entries is a statement about one moment on one
machine, not an enforcement. Read the three as:

    enforced:   NONE IN CI. The gate exists, discriminates correctly, and is
                invoked by nothing. Owner #424, which must either wire them
                into `just ci` and the workflow, or record them as manual
                instruments and return all three entries to an honest NONE.
                Sequences after #390 lands, because that PR is repairing one of
                these same gates.

This is the milestone's signature defect in its purest form. The other four
instances this week were checks that returned a verdict without
discriminating. This one discriminates perfectly and is never called. **A gate
nobody runs cannot fail**, which makes it indistinguishable from a gate that
passes.

It also re-frames a phrase used across several lanes: where a ticket says "the
mainline is red at 42 problems", that redness is a hand-run observation. No
automated check produced it, and none would have.

### An exemplar #362 must not re-invent

`gate-denominators` (#362) is commissioned to make an empty or truncated run
RED across every gate. **That pattern already exists in this repository**, in
`simulator/scenario-dsl-gate.mjs`:

    const WANT = { total: 30, checkpointFiles: 15, registryFiles: 15,
                   checkpointSteps: 104, registrySteps: 115 };

asserted by `INV-375-EXTENT`, so a run discovering fewer scenarios, files or
steps than pinned fails instead of passing on a shrunken denominator. Its
sibling `INV-375-ONE` also proves its own negative control — it asserts that a
mismatched grammar version actually throws.

Whoever takes #362 copies this. It is the same class of problem solved well one
directory away, and this milestone has already lost days once to building a
novel solution beside a sibling that had solved it.

contract:   story-record-write-partition — one narrative record, three writers
            across two epics
parties:    #418 / epic 318 (the existing text of `simulator/M1-STORIES.md`),
            #377 / epic 326 (appended sections 16+ there, and all of
            `simulator/REGISTRY-STORIES.md`), #387 (the scenario gate that
            scores both)
invariant:  no two lanes hold write scope over the same region of
            `M1-STORIES.md` or the same rows of
            `checkpoint-simulator-clauses.json`; and the landing order is
            #390 -> #418 -> #377
enforced:   **NONE**, and the NONE is honest: this is a coordination contract
            held by attention and by two epic owners' file fences. Nothing
            mechanically detects that two branches have both edited the same
            story section. Both epic owners report immediately if a child's
            diff touches a region this ruling gave to the other.
found:      2026-09-11. #377 asked its epic for write scope on `M1-STORIES.md`
            forty minutes after this desk granted #418 write scope on the same
            file in a different epic. Neither epic could see the other; the
            collision is only visible from the milestone.
why order:  #390 first because both of the others are judged by the gate it is
            repairing, and a verdict from an instrument that reads one theorem
            name thirteen times is not a verdict. #418 second: three rows, and
            it sits in the epic nine further epics wait behind. #377 third,
            rebasing onto both — its clause rows are additive, so rebasing onto
            a reclassified story-12 row is mechanical.

---

## 2026-09-11, two hours later — `story-record-write-partition` was breached,
## and the entry named the wrong parties

The partition listed #418, #377 and #387 and recorded `enforced: NONE` on the
grounds that *"nothing mechanically detects that two branches have both edited
the same story section."*

Within two hours `simulator/M1-STORIES.md` was edited **directly on `main`** by
`75401f9` (*"docs: link the KERI specification from every story page"*, #430) —
a documentation change inserting a KERI glossary into `## The words`,
immediately above the `**Checkpoint**` bullet that #418 is authorized to
correct.

**The entry's defect was not its `enforced: NONE`. It was its `parties:` line.**
A partition drawn between lanes cannot bind a writer who is not a lane, and the
writer who breached it never saw the contract and could not have. No blame
attaches to the change: it is correct, useful, and its author had no way to
know.

So the entry is corrected:

    parties:    #418 (existing text), #377 (appended sections 16+), #387 (the
                gate that scores both), and **`main` itself — any pull request
                landing an edit to `simulator/M1-STORIES.md`,
                `simulator/REGISTRY-STORIES.md` or
                `simulator/checkpoint-simulator-clauses.json`**
    enforced:   NONE, and now demonstrably so. Not even by attention: the
                breaching writer was never a party and had no notice. A
                coordination contract held by two epic owners' fences does not
                reach a third-party documentation lane.

The general lesson, which is worth more than this entry: **when a contract's
enforcement is "the parties will be careful", the entry must enumerate every
writer who can reach the artifact — not just the ones currently in view.** The
two lanes this desk could see were the two lanes that did not breach it.

Cost: the gate repair (#390) now needs a re-run it would not otherwise have
needed, because the same commit touched a file its gate reads. #418's
correction survives semantically and moves positionally.

A mechanical enforcement would be a check that a pull request touching those
three paths carries an acknowledgement of the partition. Not commissioned —
recorded here as what would close it, since an unenforced entry with no named
remedy is how #408 happened.
