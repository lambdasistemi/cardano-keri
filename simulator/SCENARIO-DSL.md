# Scenario DSL

A story author writes checkpoint or registry simulator stories in one
versioned, line-oriented language. `simulator/scenario-dsl.mjs` is the only
grammar. Both pages and the Node compiler import that file and assert
`GRAMMAR_VERSION`. The checked-in JSON files remain the scenario-gate inputs;
each `.dsl` source compiles to the same JSON.

## Compile

From the repository root:

```
node simulator/scenario-dsl-cli.mjs to-json --family checkpoint simulator/checkpoint-simulator-scenarios/01-alice-appears.dsl
node simulator/scenario-dsl-cli.mjs from-json --family checkpoint simulator/checkpoint-simulator-scenarios/01-alice-appears.json
```

`--family` is required and must match the document. Output is stdout. `--output PATH` writes a file; without it the checked-in JSON is not modified. A refusal prints `file:line: message` on stderr and exits non-zero.

## Document shape

Every document starts with the grammar version and the family:

```
grammar: 1
family: checkpoint   # or registry
```

`#` comments run to end of line outside strings. Indentation is spaces (two per level). Tabs are refused. Duplicate keys are refused. Unknown fields at the scenario, step, or fork level are refused. Numeric literals that JSON cannot represent exactly (integers beyond 2^53 − 1) are refused. The parser returns either one complete scenario or a located diagnostic; it never returns a partial story.

Repeatable section keywords `step:` and `fork:` append to `steps` and `forks`. Other keys are unique.

## Values

| form | meaning |
|---|---|
| `true` `false` `null` | booleans and JSON null |
| `0`, `1000`, `-5`, `2.5` | JSON numbers (signed integers and finite decimals) |
| `bare_word` | unquoted string of letters, digits, `_`, `.`, `-` |
| `"quoted"` | string; `\"` `\\` `\n` `\t` `\uXXXX` |
| `[a, b, c]` | list of scalars |
| `key:` plus an indented block | nested mapping or list |
| `- item` | list item |
| `{...}` or a JSON array | exact JSON when a nested tuple would be awkward |

Quote strings that contain spaces or punctuation. Keys such as `sn'` and `refund'` are legal unquoted.

## Checkpoint fields

- **story**, **title**, **goal**: identity and the user-story sentence.
- **params**: `D`, `B`, `P`, `W`.
- **atoms**: story-clause identifiers.
- **step**: `slot`, `who`, `say`; optional `action`, `evidence`, `params`, `hidden`, `expect`.
- **expect**: `ok`, `reason`, `live`, `state`, `flow`, `verdict`, `exhibits`.
- **fork**: `id`, `at` (trunk step index it departs after), `title`, then `step:` items.

A step with no `action` is a slot or evidence move. `action: poison` is a string action; `action: { register: { refund, pool0 } }` is a mapping.

## Registry fields

- **id**, **slug**, **story**, **narrative**.
- **params**: `D`, `tip`, `Mc`, `Mr`, `process`, `retract`, `W`, `far`.
- **plugin**, **actors** (address → name), **env** (evidence tables).
- **step**: `now`, `actor`, `as`, `action`, optional `expect`, `exhibits`, `note`.
- **fork**: `id`, `at`, `title`, optional `env`, `expectFinal`, then `step:` items.
- **expectFinal**: the registry after the trunk (or that fork).

## Play on the page

Each simulator page has a DSL strip under the story picker:

1. Paste text into the box and click **Load DSL**, or choose a local `.dsl` file.
2. The shared grammar parses the document. On success the story replaces the current tree through the same runner as the picker. On refusal the diagnostic shows `file:line` and the tree does not change.
3. **Copy branch** copies the origin-to-cursor free-play branch as DSL. **Download branch** saves the same text as `checkpoint-branch.dsl` or `registry-branch.dsl`.
4. Recompiling that export with `to-json` yields a scenario the existing checker accepts for the selected branch. Sibling branches off the cursor path are not included.

## Complete checkpoint example

`simulator/checkpoint-simulator-scenarios/01-alice-appears.dsl`:

```
grammar: 1
family: checkpoint

story: 1
title: "Alice's identity appears on Cardano"
goal: "As anyone holding Alice's public inception, I want to register her checkpoint, so that Cardano contracts can read her key state."
params:
  D: 1000
  B: 5
  P: 2
  W: 10
atoms: ["1.the-inception-parses-and-self", "1.the-aid-is-absent-from", "1.and-is-inserted", "1.this-is-the-only-way", "1.both-bonds-are-present"]
step:
  slot: 0
  who: treasury
  say: "Nothing on chain for this AID: the treasury fails closed, and only a registration can happen first."
  expect:
    verdict: not-present
step:
  slot: 0
  who: friend
  say: "A friend registers Alice's public inception, bringing both bonds and a first pool, and names his own refund address."
  action:
    register:
      refund: 6
      pool0: 10
  expect:
    ok: true
    live:
      sn: 0
      epoch: 0
      poisoned: false
      bornAt: 0
      refundTo: 6
      pool: 10
      frozen: false
    flow:
      dregIn: 1000
      bIn: 5
      poolIn: 10
    verdict: juvenile
    exhibits: [T3_epoch_local, T6_component_conservation, T6_dreg_enters_only_at_birth, T6_dreg_never_a_fee, T7_step_iff_stepFn, T7_trace_iff_replay, T8_absent_only_registers, T8_edges_leave_the_leaf, T8_leaf_agrees_with_state, T8_leaf_states, T8_mint_once, T8_only_convicted_is_terminal, T8_present_implies_registered, T8_sysstep_partition, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
step:
  slot: 9
  who: treasury
  say: "Nine slots later the checkpoint is still juvenile: born at slot 0, the window W is 10."
  expect:
    verdict: juvenile
step:
  slot: 10
  who: treasury
  say: "At slot 10 the treasury accepts it: both bonds full, not poisoned, past juvenility."
  expect:
    verdict: consumable
fork:
  id: nothing-yet
  at: 0
  title: "Money for a checkpoint that does not exist"
  step:
    slot: 0
    who: friend
    say: "Nothing is on chain for this AID. Money cannot be added to a checkpoint that does not exist."
    action:
      topUp:
        x: 3
    expect:
      ok: false
      reason: absent-needs-register
      verdict: not-present
      exhibits: [T7_step_iff_stepFn, T8_absent_only_registers, T8_leaf_agrees_with_state, T8_leaf_states, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
fork:
  id: zero-bond
  at: 0
  title: "A deployment with a zero bond"
  step:
    slot: 0
    who: friend
    say: "A deployment with a zero conviction bond is refused before anything else: 'bond missing' would be indistinguishable from 'bond full'."
    params:
      D: 0
      B: 5
      P: 2
      W: 10
    action:
      register:
        refund: 6
        pool0: 10
    expect:
      ok: false
      reason: invalid-params
      verdict: not-present
      exhibits: [T9_juvenility_is_consumer_only]
fork:
  id: twice
  at: 3
  title: "Registering the same AID again"
  step:
    slot: 10
    who: friend
    say: "Registering the same AID again is refused: the token is minted once, ever."
    action:
      register:
        refund: 6
        pool0: 10
    expect:
      ok: false
      reason: already-present
      verdict: consumable
      exhibits: [T10_bonds_are_observable, T7_step_iff_stepFn, T8_leaf_agrees_with_state, T8_leaf_never_absent_again, T8_leaf_states, T8_present_implies_registered, T8_utxo_iff_active, T9_juvenility_is_consumer_only, consumableStateB_iff]
```

## Complete registry example

`simulator/registry-simulator-scenarios/01-alice-requests.dsl`:

```
grammar: 1
family: registry

id: 1
slug: alice-requests
story: "Alice posts a registration request"
narrative: "Anyone holding Alice's public inception creates a request UTxO at the cage: her AID, her refund address as owner, the bond D and the tip. Nothing contends; the registry is untouched."
params:
  D: 1000
  tip: 2
  Mc: 4
  Mr: 1
  process: 10
  retract: 10
  W: 5
  far: 1000000000
plugin: 7
actors:
  1: Alice
  2: Bob
  3: "Hal (folder)"
  4: Mallory
  5: "Cora (convictor)"
  6: "Sam (reaper)"
env:
  inception: [11]
step:
  now: 0
  actor: anyone
  as: Alice
  action:
    contribute:
      aid: 11
      owner: 1
      submittedAt: 0
      op: register
  expect:
    ok: true
    flow:
      deposited: 1002
  exhibits: [R6, R11]
  note: "The generation is still 0: a request never spends the cage."
fork:
  id: mallory-go
  at: 1
  title: "Mallory posts a go-request by hand"
  expectFinal:
    gen: 0
    plugin: 7
    leaves: []
    ckpts: []
    requests: [{"id":0,"aid":11,"owner":1,"submittedAt":0,"op":"register"}]
    nextReq: 1
    nextToken: 0
  step:
    now: 0
    actor: anyone
    as: "Mallory — posting a go-request by hand"
    action:
      contribute:
        aid: 11
        owner: 4
        submittedAt: 0
        op: goConvicted
    expect:
      ok: false
      reason: not-postable
    note: "Only a reap of a bondless checkpoint creates a go-request."
expectFinal:
  gen: 0
  plugin: 7
  leaves: []
  ckpts: []
  requests: [{"id":0,"aid":11,"owner":1,"submittedAt":0,"op":"register"}]
  nextReq: 1
  nextToken: 0
```
