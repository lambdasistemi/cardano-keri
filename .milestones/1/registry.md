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
