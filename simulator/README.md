# The checkpoint simulator

A single page that plays the M1 checkpoint machine of
`lean/CardanoKeri/Checkpoint.lean` and shows the theorems T1–T16 of
`lean/CardanoKeri/CheckpointGoals.lean` holding on every step. The Lean is
the specification; the page is a transcription of it, and two gates keep the
transcription honest against the Lean itself.

## Open it

- Published with the docs: `docs/simulator/index.html` (nav entry
  *Checkpoint Simulator*), byte-identical to `simulator/checkpoint-simulator.html`.
- Locally: open `simulator/checkpoint-simulator.html` in a browser. No
  framework, no CDN, no network request; light and dark theme.
- Self-test: open it with `?selftest=1`. The page replays the fifteen stories
  and the embedded Lean corpus through its own inlined core and checks every
  theorem on every replayed step; it prints PASS/FAIL per item and puts the
  verdict in the tab title.

The page is one scene: KERI on the left (Alice with the epoch of her keys,
her witnesses, Cora, Mallory, anyone), the Cardano UTxO in the middle (the
token, the datum, the three coin piles D / B / pool, the juvenility bar, the
registry, the validator and the tray of evidence presented), the readers and
payees on the right (Hal, a rival hunter, the treasury reading the checkpoint
with its verdict lamp, the wallets that receive payments). Every step plays
on it: the transaction flies from the actor to the validator and gets its
✓ or ✗ with the reason, the rotation arrives from the witnesses, coins move
from piles to wallets exactly as the flow record says, the datum pulses, a
poison drops its ☠, a freeze lifts the freeze bond out, a conviction turns
the token into a tombstone, a close burns it, a slot move turns the clock.

A story is a tree: its trunk and the branches it implies (`forks` in the
scenario file). ‹ goes back one step and plays the step in reverse; › goes
forward along the branch last taken; ⇤ ⇥ jump to the start and to the end
of the branch; the scrubber runs over the current branch; ▶ plays it; the
⋔ chips switch branch at a fork; ← → and space do the same from the
keyboard. Free play forks the same way: an action taken from a step that
already has a continuation opens a sibling branch instead of erasing the
future. Choose an actor (click one on the scene or in the Act drawer), add
evidence (a witnessed rotation, a quorum signature, a duplicity proof — the
validator's cryptographic checks, abstracted to a table you decide), move the
slot forward, submit an action. Every action the machine would refuse is
offered disabled with the reason in the story's words. The numbers, the
value chart and the balances live in drawers under the theorem lamps.

## Files

| file | role |
|---|---|
| `checkpoint-simulator-core.mjs` | the pure core: `step` (= `stepFn`), `replay`, `consumable` (= `consumableState`), sessions, the story vocabulary, the theorems as executable properties, the scenario/corpus checkers. No DOM, no storage, no clock. |
| `checkpoint-simulator.html` | the page; the core's slices are inlined between `@@CORE:<id>@@` markers, the scenarios between `@@SCENARIOS@@`, the Lean corpus (with its sha256) between `@@CORPUS@@`. |
| `checkpoint-simulator-build.mjs` | regenerates the page from the core, the scenarios and the corpus, and writes `docs/simulator/index.html`; `--check` reds on any drift. |
| `checkpoint-simulator-scenarios/` | one JSON per story (1–15): params, evidence decisions, actions with slots and actors, expected results per step including refusal reasons, the theorems each step exhibits. |
| `checkpoint-simulator-scenario-gate.mjs` | replays every scenario through the core with the Lean corpus as T7's oracle; every theorem on every step; every refusal reason asserted; exact Nat at every real entry point; a multi-AID system generator (T8 on every transition); the story reconciliation against the Lean's declaration spans and the distinctive-clause matrix (`--matrix`, `--clauses-md`); build drift; a page smoke under a minimal DOM including `?selftest=1`. `--selftest` proves it can fail twenty ways. |
| `checkpoint-simulator-corpus.json` | the output of `lean/CheckpointTraceDriver.lean`, verbatim: seeded traces, the boundary grid, and the Lean's own verdict on every step of the fifteen scenarios (the T7 oracle). |
| `checkpoint-simulator-clauses.json` | every "chain checks" clause of every story reconciled with the Lean (guard or overrule anchored inside a Lean declaration with a semantic tie, omission with its note) and the distinctive clauses each scenario must exercise. |
| `M1-STORIES.md` | the fifteen stories, verbatim, which the gate reads to extract the clauses. |
| `checkpoint-simulator-trace-gate.mjs` | builds the driver's Lean imports (`lake build`), runs the Lean driver fresh, compares by sha256 with the corpus embedded in the page, replays every step (applied and refused) through the core and the page's inlined core, checks every theorem on every applied step. `--selftest` proves it can fail, cold included. |
| `checkpoint-simulator-minidom.mjs` | the minimal DOM the gates drive the page with (parser, selectors, events, values, a recording canvas). Not jsdom: what the page uses and it lacks throws. |
| `../lean/CheckpointTraceDriver.lean` | a program, imported by nothing: runs `stepFn` over seeded traces, a boundary grid (every guarded comparison at −1 / = / +1, every action from every state, two evidence oracles) and every step of the scenario files, and prints JSON via `ToJson` instances. |

## Run the gates

```sh
node --check simulator/checkpoint-simulator-core.mjs
node simulator/checkpoint-simulator-build.mjs --check
node simulator/checkpoint-simulator-scenario-gate.mjs
node simulator/checkpoint-simulator-trace-gate.mjs      # builds and runs Lean via nix shell nixpkgs#lean4 (see the prerequisite below)
nix develop 'github:paolino/dev-assets?dir=mkdocs' --quiet -c mkdocs build --strict --site-dir /tmp/sim-site
```

After editing the core, a scenario or the driver:

```sh
(cd lean && nix shell nixpkgs#lean4 -c lake env lean CheckpointTraceDriver.lean) > simulator/checkpoint-simulator-corpus.json
node simulator/checkpoint-simulator-build.mjs
```

Negative controls, each RED for its intended reason, then GREEN:

```sh
node simulator/checkpoint-simulator-scenario-gate.mjs --selftest   # flipped expectation, flipped guard, lying property, broken control, rounding at 2^53, step / replay / consumable / corpus verifier with its boundary removed, wrong transition (T7), registry drop (T8), W read (T9), dropped clause, the auditor's unrelated-declaration survivor, same text on another constructor, text outside the declaration, step through another constructor, clause absent from the story, a Lean guard hypothesis renamed, dropped distinctive step
node simulator/checkpoint-simulator-trace-gate.mjs --selftest      # mutated post-state, emptied corpus, mutated sha, flipped guard, then the cold control (a copy of lean/ without .lake fails with the build step removed and is byte-identical with it)
```

### Prerequisite of the trace gate

The trace gate runs the Lean driver with `lake env lean`, which resolves
`import CardanoKeri.Checkpoint` only from built `.olean` files under the
ignored `lean/.lake/`. The gate therefore runs `lake build` on the modules
the driver imports before the driver (a no-op when the build is current, a
few seconds from a fresh clone or worktree), through `nix shell
nixpkgs#lean4`. Nothing has to be built by hand; if the build fails the gate
prints the exact command to run from `lean/` to see why.

## Numbers

A Lean `Nat` is unbounded; this simulator represents it exactly up to
2^53 − 1 and refuses by name (`invalid-nat`, with the offending field)
anything else at every entry point that takes a state or an evidence table —
`step`, `replay`, the system step `attempt`, the consumer predicate
`consumable`, the corpus verifier `checkCorpus` — before anything is
evaluated: the complete state (every datum or tombstone field) and the
complete table (every row of every predicate, consulted or not) are checked
first, in the order params, slot, action, state, evidence. A shape that is
not one of the four Lean states is `invalid-state`; a table that is not the
four predicates with their arities is `invalid-evidence`; the consumer's
verdict on such input is the refusal itself. An arithmetic result beyond the
bound is refused too. Nothing is ever rounded.

## The reconciliation table

`checkpoint-simulator-clauses.json` classifies every "chain checks" clause of
every story, split into atomic claims, as a guard (the Lean decides it), an
omission (the Lean does not model it) or an overrule (the Lean decides
differently). A guard or overrule row is one claim of one kind — `guard` (a
hypothesis the transition requires), `refusal` (the clause states a
refusal), `payment` (a flow field pays it), `post-state` (the resulting
state, optionally `updates`: the only datum fields it sets), `no-guard` (the
constructor has no hypothesis), `verdict` (a conjunct of `consumableState`)
— and names a Lean declaration (a `Step` constructor, `consumableState`,
`SysStep.register`, `Trace.cons` or a theorem), the hypothesis for a guard or
refusal, the exact text that entails the claim, and one semantic tie: a
refusal name (the core's `LEAN_GUARDS` table binds every refusal name to the
constructor and binder that refuse it; a refusal claim's story must also be
refused for it), a consumer verdict (bound to its conjunct), or a step of
the story's own scenario (whose constructor is derived from the record; a
payment's step must pay through the named field, an `updates` claim's step
must change nothing else). The scenario gate parses the Lean into declaration
and constructor spans, splits each constructor's conclusion into its
hypotheses, flow record and post-state, and requires the text inside the
part its kind names, the tie to hold, every clause to occur in its story,
and every guard hypothesis of every `Step` constructor to be claimed by
exactly one refusal name (or by the paid/unpaid split). `--clauses-md`
renders the table.

## The theorem ledger

Each row lights when the step shows the theorem (its antecedent held) and is
checked on every step regardless. T7 is parity with the Lean: a step is
compared with the Lean's own verdict for it when the embedded corpus has a
cell (every story step, the grid, the seeded traces); with no cell it is not
shown and the row says so.

## What is modelled

From the Lean's own statements (`Checkpoint.lean`, module comment and
constructors):

- states Absent, Present (live / poisoned / frozen / paused, read off the
  datum), Convicted (terminal), Gone (terminal);
- actions register, rotate (keep / withdraw / deposit, payee, optional new
  refund address), poison, freeze, top-up, convict, close — exactly the
  redeemers of the validator family;
- evidence as decidable predicates: a witnessed rotation, a refund address
  signed by the new keys, the current quorum, a duplicity proof;
- value as three addressed components — conviction bond `D`, freeze bond `B`,
  pool — that never mix; payments to the refund address, a hunter, a convictor;
- the consumer's state-side check: both bonds full, not poisoned, born at
  least `W` slots ago;
- the fold: the state is the replay of the accepted actions; a trace needs
  non-decreasing slots;
- one incarnation per AID (the registry; one AID is played here).

## What is not modelled

Also from the Lean: no cryptography (keys are an epoch counter; evidence is a
table); validity (D-027, A11) is reserved in the datum and not modelled; the
consumer's own threshold check is the consumer's; no UTxO mechanics (story 14's
"spent input" appears as evidence that no longer matches); delegated
identities, record trees, interactions, hunter bounties, conviction that
clears — none, by design. Two open details of D-034 are fixed as modelling
assumptions in the Lean and therefore here: no freeze from a poisoned state;
conviction sends the freeze bond and the pool to the refund address.

Deployment values used by every story: `D` = 1000, `B` = 5 (preprod), `P` = 2,
`W` = 10 slots (chosen here; the stories call `P` and `W` new).

Where the Lean did not let the builder decide, and where a story or a doc
comment disagreed with a definition, the record is `LEAN-CLARITY.md` in the
build's handoffs.
