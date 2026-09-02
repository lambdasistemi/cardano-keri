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

Pick a story from the picker and step through it with ⏮ ‹ › ⏭; or play
freely: choose an actor, add evidence (a witnessed rotation, a quorum
signature, a duplicity proof — the validator's cryptographic checks,
abstracted to a table you decide), move the slot forward, submit an action.
Every action the machine would refuse is offered disabled with the reason in
the story's words.

## Files

| file | role |
|---|---|
| `checkpoint-simulator-core.mjs` | the pure core: `step` (= `stepFn`), `replay`, `consumable` (= `consumableState`), sessions, the story vocabulary, the theorems as executable properties, the scenario/corpus checkers. No DOM, no storage, no clock. |
| `checkpoint-simulator.html` | the page; the core's slices are inlined between `@@CORE:<id>@@` markers, the scenarios between `@@SCENARIOS@@`, the Lean corpus (with its sha256) between `@@CORPUS@@`. |
| `checkpoint-simulator-build.mjs` | regenerates the page from the core, the scenarios and the corpus, and writes `docs/simulator/index.html`; `--check` reds on any drift. |
| `checkpoint-simulator-scenarios/` | one JSON per story (1–15): params, evidence decisions, actions with slots and actors, expected results per step including refusal reasons, the theorems each step exhibits. |
| `checkpoint-simulator-scenario-gate.mjs` | replays every scenario through the core and the page; every theorem on every step; every refusal reason asserted by some story; build drift; a page smoke under a minimal DOM. `--selftest` proves it can fail. |
| `checkpoint-simulator-corpus.json` | the output of `lean/CheckpointTraceDriver.lean`, verbatim (seeded traces and the boundary grid). |
| `checkpoint-simulator-trace-gate.mjs` | runs the Lean driver fresh, compares by sha256 with the corpus embedded in the page, replays every step (applied and refused) through the core and the page's inlined core, checks every theorem on every applied step. `--selftest` proves it can fail. |
| `checkpoint-simulator-minidom.mjs` | the minimal DOM the gates drive the page with (parser, selectors, events, values, a recording canvas). Not jsdom: what the page uses and it lacks throws. |
| `../lean/CheckpointTraceDriver.lean` | a program, imported by nothing: runs `stepFn` over seeded traces and a boundary grid (every guarded comparison at −1 / = / +1, every action from every state, two evidence oracles) and prints JSON via `ToJson` instances. |

## Run the gates

```sh
node --check simulator/checkpoint-simulator-core.mjs
node simulator/checkpoint-simulator-build.mjs --check
node simulator/checkpoint-simulator-scenario-gate.mjs
node simulator/checkpoint-simulator-trace-gate.mjs      # runs Lean via nix shell nixpkgs#lean4
nix develop 'github:paolino/dev-assets?dir=mkdocs' --quiet -c mkdocs build --strict --site-dir /tmp/sim-site
```

After editing the core, a scenario or the driver:

```sh
(cd lean && nix shell nixpkgs#lean4 -c lake env lean CheckpointTraceDriver.lean) > simulator/checkpoint-simulator-corpus.json
node simulator/checkpoint-simulator-build.mjs
```

Negative controls, each RED for its intended reason, then GREEN:

```sh
node simulator/checkpoint-simulator-scenario-gate.mjs --selftest   # flipped expectation, flipped guard, lying property, broken control
node simulator/checkpoint-simulator-trace-gate.mjs --selftest      # mutated post-state, emptied corpus, mutated sha, flipped guard
```

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
