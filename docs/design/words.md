# The project's words

You are reading these pages for the first time, and every page uses the same
dozen words: poison, hunter, pool, premium, the reap, parked. This page is
where each of them is decided: what it means, why it was kept when readers
objected to it, and what it was kept over. Every other page repeats the
meaning in one clause the first time it uses the word, so you never need to
come back here; this page exists so that the clause is the same everywhere.

The words below are the project's own. KERI's words — AID, KEL, inception,
rotation, witness, toad, receipt, duplicity — keep KERI's meaning; the
[KERI primer](../keri-primer.md) introduces them and the simulator's story file
links each to its clause of the specification.

## Where the words sit

```mermaid
flowchart TB
    start(( )) --> Absent["<b>Absent</b><br/>register — the conviction bond D_reg, the freeze bond B and the pool are posted"]
    Absent -->|register| Active["<b>Active</b><br/>rotate — a hunter lands it and is paid the premium P from the pool<br/>poison — the owner's lock#59; any witnessed rotation clears it<br/>freeze — a hunter takes B when the pool cannot pay<br/>deposit — a rotation that refills B"]
    Active -->|the reap| Parked["<b>Parked</b><br/>the reap — a rotation by the next keys closes the checkpoint#59; the output retains the token and key state<br/>reopen — a later witnessed rotation from the parked key state"]
    Parked -->|reopen| Active
    Active -->|duplicity proof| Pending["<b>Pending conviction</b><br/>retained custody#59; no local exit"]
    Parked -->|duplicity proof| Pending
    Pending -->|associated consuming Registry fold| Convicted["<b>Convicted</b><br/>token burned#59; registry key permanently retired"]
```

A consumer trusts an active checkpoint only once it is older than the
juvenility window `W`. A parked KERI output retains its token, minimum ADA
and last key state, while the registry key stays active; consumers refuse it.

The owner’s close pays the addressed D/B/pool flows defined by Checkpoint.
`Samaritan.Reap` instead describes termination booking after conviction.
Its booker avoids a loss only when the booking premium covers the external
booking fee. Addressed self-fold recovery has additional accepted-fold and
output-destination premises.

## The decision record

Two independent readers of the onboarding material, in September 2026, met
these words on every page before any page defined them, and objected to some
of the names themselves. The table records each objection, the alternatives
weighed, and the outcome. The outcome for every word is *keep and define*: a
rename would also rename a Lean definition, a simulator transition or a
planned `ckeri` command, and that cost is recorded in the last column rather
than paid here.

| Word | What it means (the clause every page uses) | The readers' objection | Alternatives weighed | Outcome and the cost of renaming |
|---|---|---|---|---|
| **poison** | The owner's own lock on the checkpoint: a declaration signed by the current keys at their threshold that makes the checkpoint unconsumable until a witnessed rotation clears it. | Reads as an attack on the identity when it is the owner's defence against a thief holding the current keys. | *lock* (collides with locking a UTxO at a script), *hold* and *seal* (ACDC and KERI already use *seal*), *alarm*. | Keep and define. Renaming touches `Checkpoint.lean`, both simulators and the planned `ckeri poison` command. |
| **hunter** | Anyone paid to land an owner's rotation on chain, or to freeze a checkpoint whose pool cannot pay for one. | Reads as a bounty hunter, when the ordinary paid work is relaying valid rotations. | *relayer* (already names the unpaid role that submits what the owner signed), *keeper* (another ecosystem's word), *operator* (collides with the stake-pool operator). | Keep and define. The simulator's cast, the Lean economics and the planned hunter daemon all use it. |
| **juvenility window** `W` | The age a checkpoint must reach, counted from its last registration or reopening, before a consumer trusts it. | Infantilises what is a consumer-side aging rule. | *maturity window*, *settling window*, *aging window*, *quarantine*. | Keep and define. `W`, `born_at` and the refusal `juvenile` are in the Lean, the API and the simulators. |
| **the reap** | The owner's only close: a witnessed rotation by the *next* keys that names who is paid the premium and where the bonds go, while retaining the token, minimum ADA and reached key state in a parked output; the registry key stays active. | An agricultural metaphor; and older pages used *reap* for something else, a hunter consuming a paused checkpoint after a grace period. | *close* (kept as the operation name), *leave*, *retire*. | Keep and define; the older meaning is retired with the enforcement economy and no longer appears. Local close uses Checkpoint’s addressed D/B/pool flows. `Samaritan.Reap` instead models termination booking after conviction. |
| **the cage** | An MPFS store: a Merkle Patricia Forestry map whose every update passes through one validator. The registry is such a store, made permissionless. | Undefined jargon on the pages that use it. | *store*, *vault*, *registry contract*. | Keep and define. It is the MPFS project's own word for the pattern. |
| **the samaritan** | The economic role of a termination booker or folder. `Samaritan.Reap` models the convicted carrier’s booking split: carrier minimum ADA funds request minimum ADA plus declared tip, and the remainder is the booking premium. Booker non-loss requires that premium to cover the external booking fee; self-fold recovery also requires the theorem’s accepted-fold and addressed-output premises. | Appears as a Lean file name in prose, undefined. | *reaper*, *applier*. | Keep, define, and confine it to the registry design page. |
| **parked** | A retained KERI output holds the representative token, minimum ADA and last key state; the registry key stays active. A later witnessed rotation from precisely that state consumes the output and revives the identity with fresh bonds. | None; the objection was to its undefined use. | *dormant*, *closed*, *tombstoned* (the last two name states the design no longer has). | Keep and define. |
| **convicted** | The terminal state after a duplicity proof and its associated consuming Registry fold. The proof first enters pending custody; a live conviction pays the conviction bond to the prover, while a parked conviction has no bonds to pay. Nothing reopens the retired identity. | None; the objection was to its undefined use. | *tombstoned*, *burned*. | Keep and define. |
| **freeze bond** `B` | What a hunter takes when the owner's pool cannot pay for a rotation; a `deposit` rotation refills it. | Older pages call the same money the *delay bond*. | *delay bond* (the retired enforcement economy's name). | Keep and define; *delay bond* is not used for the accepted design. |
| **conviction bond** `D_reg` | The stake a duplicity proof seizes. Never a fee source. | Older pages call it the *divergence bond*, the *registration bond* or the *deposit*. | *registration bond* (survives only as the shipped V1 deployment parameter). | Keep and define. |
| **the pool** | The owner's advance funds, from which the premium is paid; anyone may top it up. | Collides with the *witness pool* and the *stake pool*. | *advance fund*, *purse*. | Keep and define; the other two pools are always written with their qualifier. |
| **premium** `P` | The fee the pool pays whoever lands a rotation. | None; the objection was to its undefined use. | *fee*, *bounty* (retired with the enforcement economy), *tip* (the registry's word for the same idea). | Keep and define. |

## The name of the design

Issues, pull requests and the wiki from September 2026 call the design *the
M1 return*: the return, inside the first milestone, from an abandoned
enforcement economy to a checkpoint that only projects key state. The name
tells a newcomer nothing, so reader-facing pages say **the accepted design**
instead, and the [home page](../index.md#how-to-read-these-pages) and the
[roadmap](../roadmap.md) each carry one sentence explaining the old name so
that the older record stays readable.

## Where else the words are fixed

- The simulator's story file, `simulator/M1-STORIES.md`, carries a glossary
  with the same clauses.
- The [consumer checklist](../user/consumer-checklist.md) is the shortest
  page that uses most of them, and a good place to see the clauses in use.
