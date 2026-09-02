# The M1 checkpoint simulator

A single-page, dependency-free simulator of the M1 checkpoint machine, on
the pattern of the Reactivegas economics simulator: a person can play the
fifteen stories (`handoffs/M1-STORIES.md` in the M1 runtime root) against
the exact machine the Lean model defines — `lean/CardanoKeri/Checkpoint.lean`,
theorems in `lean/CardanoKeri/CheckpointGoals.lean`.

The JavaScript core is a **transcription of `stepFn`**: same actions, same
guards (tested in the constructor's own conjunction order), same flows, same
results, same refusals. Where `stepFn` returns `none`, the core refuses with
a named reason. Nothing on the page decides anything the core does not.

## How to open

Open `simulator/checkpoint-simulator.html` in any browser — double-click it,
or `nix shell nixpkgs#nodejs -c npx serve simulator` if you prefer a server.
No framework, no CDN, no external request: the machine core, the fifteen
stories and the frozen Lean trace corpus are embedded in the page.

- Pick one of the fifteen stories and play it step by step, or play freely:
  the evidence panel is the four `Env` predicates — *you* (or the story)
  decide what evidence exists; the machine only ever applies it.
- The checkpoint card shows the datum, the three value components (which
  never mix) as bars, and the treasury's verdict with the failing conjunct
  named.
- The history strip (⏮ ‹ ›) time-travels over every accepted and refused
  attempt.
- `?selftest` replays every story and the embedded Lean corpus through the
  page's own core and prints PASS/FAIL.
- Light and dark themes; `◐` toggles.

## How to run the gates

```sh
cd /code/cardano-keri-m1-return-sim
node --check simulator/checkpoint-simulator-core.mjs          # the core parses
node simulator/checkpoint-simulator-build.mjs                 # page = core + stories
node simulator/checkpoint-simulator-scenario-gate.mjs         # 15 stories, both surfaces
node simulator/checkpoint-simulator-trace-gate.mjs            # fresh Lean vs embedded corpus
```

The trace gate runs Lean itself (`nix shell nixpkgs#lean4 -c lake build
CardanoKeri.Checkpoint` then `nix shell nixpkgs#lean4 -c lake env lean
CheckpointTraceDriver.lean` from `lean/`), compares the fresh output against
the embedded fixture by sha256, and replays every step through the page's
production JavaScript.

Each gate is proven able to fail, permanently, via `--selftest`
(negative controls on scratch copies — the committed tree is never touched):

```sh
node simulator/checkpoint-simulator-scenario-gate.mjs --selftest
node simulator/checkpoint-simulator-trace-gate.mjs --selftest
```

The scenario gate selftest breaks a story expectation, forks an embedded
byte, and flips a core guard (an M-class mutant in the style of
`lean/CHECKPOINT-MUTANTS.md`); the trace gate selftest mutates a post-state,
empties the corpus, and mutates the stated sha. Every control must go RED
for the intended reason before production GREEN.

## The files

| file | role |
|---|---|
| `checkpoint-simulator-core.mjs` | the one transcription: `step`, `replay`, `consumableState`, `envFromTables`, named refusal reasons, trace-envelope and scenario verifiers |
| `checkpoint-simulator.html` | the page; embeds the core byte-for-byte between `@@CORE:` markers |
| `checkpoint-simulator-build.mjs` | regenerates the page from the core and the stories; `--check` reds on drift |
| `checkpoint-simulator-scenarios/` | the fifteen stories as executable data: initial params, evidence tables, actions with slots, expected flows/states/refusals, consumer checks |
| `checkpoint-simulator-scenario-gate.mjs` | replays every story through the core module *and* the page's own script; proves one core |
| `checkpoint-simulator-trace-gate.mjs` | runs the Lean driver, compares by hash, replays through the page |
| `../lean/CheckpointTraceDriver.lean` | the durable producer: six seeded traces (happy path, freeze→unfreeze, pause→resurrect, poison→rotate, convict, close) folded through `stepFn`, serialized with `ToJson` — imported by nothing, a program |

## What is modelled, and what is not

Modelled, exactly as `lean/CardanoKeri/Checkpoint.lean`: states (absent,
present, convicted, gone), the seven actions, the four evidence predicates
as guards, addressed component-wise flows, the registry rule that
registration is mint-once (`Sys`), and `consumableState` — the state-side
conjuncts a consumer checks.

Two open details of D-034 are fixed in the Lean model as **modelling
assumptions**, and this simulator inherits them verbatim:

1. **A freeze is not enabled from a poisoned state.** (The datum is already
   unconsumable there; freezing would take the hunter's bounty from someone
   already down.)
2. **A conviction sends the freeze bond and the pool to the refund address
   while the conviction bond goes to the convictor.** (`D_reg` is seized in
   full by the proof and is never a fee source; the rest goes home.)

Also outside the machine, by design: validity (D-027, A11) is reserved in
the datum and not modelled; the consumer's own threshold signature on its
payment is the consumer's check, outside this machine — `consumableState`
names exactly the state-side conjuncts. No cryptography: keys are abstracted
to an epoch counter, evidence to decidable predicates the player decides.
