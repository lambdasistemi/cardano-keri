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

The page reads top-down as where we are and what can happen next. First the
play: the tree of it, drawn (every step a node — ✓ accepted, ✗ refused, ⏱ a
slot move, ≡ evidence — labelled with the actor and what they did: `Alice
register`, `Mallory close`, `Alice rotate·withdraw`, `treasury slot 40` — every
branch a line, ⋔ at a fork, the ring on the current step; click a node to jump
there), the play bar, one strip with the
state word, the keys, the treasury's verdict and the three sums, and the
narration of the current step. Then the main panel, what can happen next:
the story's continuations from here (the one › will take marked, the other
branches with their titles) and every move the machine would accept from
here grouped by actor, the evidence each can bring, the time moves, and the
refused moves folded with their reasons. Then the scene, collapsible.

The scene: KERI on the left (Alice with the epoch of her keys,
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
| `checkpoint-simulator-core.mjs` | the pure core: `step` (= `stepFn`), `replay`, `consumable` (= `consumableStateB`, the Lean's own decidable mirror of `consumableState`, tied by `consumableStateB_iff`), sessions, the story vocabulary, the theorems as executable properties, the scenario/corpus checkers. No DOM, no storage, no clock. |
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
  datum), Closed (the tombstone: epoch and sequence of the closing rotation;
  not terminal, D-036), Convicted (the only terminal state);
- actions register, rotate (keep / withdraw / deposit, payee, optional new
  refund address), poison, freeze, top-up, convict, close (a witnessed
  rotation that withdraws everything and burns, poisoned or not, D-036),
  reopen (a witnessed rotation later than the tombstone, fresh bonds, born
  again) — exactly the redeemers of the validator family;
- evidence as decidable predicates: a witnessed rotation, the intent the
  new keys signed — a bond option other than keep, a close, or a new refund
  address, in one message (D-038: a relayer with public data lands a keep
  and nothing else), the current quorum, a duplicity proof;
- value as three addressed components — conviction bond `D`, freeze bond `B`,
  pool — that never mix; payments to the refund address, a hunter, a convictor;
- the consumer's state-side check: both bonds full, not poisoned, born at
  least `W` slots ago;
- the fold: the state is the replay of the accepted actions; a trace needs
  non-decreasing slots;
- one incarnation per AID: the registry as a map from AID to a leaf —
  absent, live, closed, convicted — that follows the state; register needs
  an absent leaf, reopen a closed one; rotate, poison, freeze and top-up
  never touch it (D-037; the MPFS mechanics are outside the machine).

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

---

# The registry simulator

A second page on the same pattern for the AID registry as an MPFS instance:
the machine of `lean/CardanoKeri/Registry.lean`, the theorems R1–R14 of
`lean/CardanoKeri/RegistryGoals.lean`, fifteen stories told as trees
(`REGISTRY-STORIES.md`, a trunk and the branches where an attempt is refused
or the world differs), their clauses reconciled with the Lean
(`registry-simulator-clauses.json`), the clarity record of what the Lean left
open (`REGISTRY-LEAN-CLARITY.md`), and two gates that keep the transcription
honest against the Lean. The shape follows the `simulate-lean-state-machine`
skill; this suite is its functional-machine instance (no `Step` relation:
`stepFn` is the machine, its `if` conjuncts and refusing `match` arms are the
decision sites). The design note is `docs/design/registry-as-mpfs.md`; the
generic cage and the permissioning divergence are `lean/CardanoKeri/Cage.lean`;
the reaper's economics are `lean/CardanoKeri/Samaritan.lean`.

## Open it

- Published with the docs: `docs/simulator/registry/index.html` (nav entry
  *Registry Simulator*), byte-identical to `simulator/registry-simulator.html`.
- Locally: open `simulator/registry-simulator.html`. No framework, no CDN, no
  network request; light and dark theme; `?selftest=1` replays the fifteen
  stories and the embedded Lean corpus through the page's own core.

Pick a story: the play is drawn as a tree (✓ applied, ✗ refused; a ⋔ branch
departs where it starts; click a node to go there) and *what can happen next*
lists the continuations — the next step, or a branch. Or play freely: post requests (register,
revive, convict a dormant AID), decide the evidence (inceptions, witnessed
rotations from a key state, duplicity proofs against a key state, the owner's
quorum), move the slot, build a fold by choosing what to do with each pending
request, retract, pause and resume a checkpoint, convict one, reap one. Every
refusal is named after the Lean guard that refused it, in the story's words.

## Files

| file | role |
|---|---|
| `registry-simulator-core.mjs` | the pure core: `step` (= `stepFn`), `processBody`, `rejectOne`, `applyBatch`, `batchView` (what each position of a batch saw), `reapableReason`, `replay`, the phases, exact Nat on inputs and results, the guard table (`LEAN_GUARDS`: refusal name → decision sites of the Lean), R1–R14 as executable properties over the accumulator (each names the Lean theorem the step instantiated), `findLeanCell` (T7 for any step: the Lean's cell in the corpus), the scenario (tree) and corpus checkers |
| `registry-simulator.html` | the page; core slices between `@@CORE:<id>@@`, stories between `@@SCENARIOS@@`, the Lean corpus with its sha256 between `@@CORPUS@@` |
| `registry-simulator-build.mjs` | regenerates the page and `docs/simulator/registry/index.html`; `--check` reds on any drift |
| `registry-simulator-scenarios/` | one JSON per story (1–15): params, plugin, evidence table, a trunk of steps and `forks` (`id`, `at`, `title`, an optional `env` of its own, steps), expected results per step including refusal reasons and flows, the theorems each step exhibits |
| `registry-simulator-clauses.json` | the reconciliation table: 103 atomic claims over the stories' labelled bullets, each a Lean declaration, arm, exact text, kind (guard / refusal / payment / post-state / no-guard / verdict) and one tie (a refusal name, or a step of the story); one omission (the retract's signer) |
| `REGISTRY-LEAN-CLARITY.md` | what the Lean left open and what was decided (D-R1…), the questions escalated with their evidence (Q-R1…), the prose that disagreed with the definitions and how it was fixed |
| `registry-simulator-scenario-gate.mjs` | every branch of every story through the core with the Lean corpus as the parity oracle; every property on every step; every reachable refusal reason asserted (two guards are unreachable by `Inv` and exempted by name); exact Nat and shapes at every entry point and every successor, sum and product at the bound; a fabricated violation per lamp; the clauses against the Lean's declaration spans and the guard table both ways (every decision site on the path from `stepFn` claimed); build drift; the page under the minimal DOM (selftest, every story, a branch taken through the tree, free play). `--selftest` proves twenty-two ways it can fail; `--clauses-md` prints the table |
| `registry-simulator-corpus.json` | the output of `lean/RegistryTraceDriver.lean`, verbatim: six seeded traces, the boundary grid, the Lean's verdict on every step of the fifteen stories and their thirteen forks; the grid at slots 19, 20 and 21 puts every guarded comparison at −1 / = / +1 (3163 cells) |
| `registry-simulator-trace-gate.mjs` | builds the driver's imports and runs the Lean driver fresh, compares by sha256 with the committed corpus and the embedded copy, replays every cell through the core and the page's inlined core. `--selftest` proves six ways it can fail, then the cold control: a copy of `lean/` without `.lake` fails with the build step removed and is byte-identical with it |
| `REGISTRY-STORIES.md` | the fifteen stories, each with its labelled bullets (the checked prose) and its branches |
| `../lean/RegistryTraceDriver.lean` | a program, imported by nothing: runs `stepFn` over the seeds, the grid and the scenario files and prints JSON via `ToJson` |

## Run the gates

```sh
node --check simulator/registry-simulator-core.mjs
node simulator/registry-simulator-build.mjs --check
node simulator/registry-simulator-scenario-gate.mjs
node simulator/registry-simulator-trace-gate.mjs      # builds and runs Lean via nix shell nixpkgs#lean4
node simulator/registry-simulator-scenario-gate.mjs --selftest
node simulator/registry-simulator-trace-gate.mjs --selftest
```

After editing the core, a scenario or the driver:

```sh
(cd lean && nix shell nixpkgs#lean4 -c lake env lean RegistryTraceDriver.lean) > simulator/registry-simulator-corpus.json
node simulator/registry-simulator-build.mjs
```

## What is modelled

From the Lean's own statements: leaves active / dormant / convicted;
checkpoints live / parked / tombstone; requests as inbox UTxOs for
registration, revival and conviction of a dormant AID; go-requests created
only by a reap and dated at the end of time; the fold (process / reject per
request) at a named generation; retract; pause, resume and conviction of a
checkpoint; the reap and its value split; four evidence predicates. Not
modelled: cryptography, rotations that keep a checkpoint live, the
checkpoint's bonds beyond one abstract `D`, fees (parameters of the
samaritan theorems), the receipt token, and which of two racing folders wins.
