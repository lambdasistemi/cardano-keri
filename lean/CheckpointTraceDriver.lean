import CardanoKeri.CheckpointTraceWire

/-!
# Checkpoint trace driver

A program, imported by nothing. It runs `stepFn` of `CardanoKeri.Checkpoint`
over seeded traces and over a boundary grid and prints one JSON document
that `simulator/checkpoint-simulator-trace-gate.mjs` compares by sha256
with the corpus embedded in `simulator/checkpoint-simulator.html`, then
replays through the page's JavaScript core. Every value is serialized by
Lean `ToJson` instances — never `Repr` parsing — so the shapes the
JavaScript must match are the ones Lean chooses.

Run from `lean/`:

```sh
lake env lean CheckpointTraceDriver.lean
```

Refused steps are emitted as `result: null`, so refusal parity with the
Lean is a gate and not a reading. The seeded traces continue past a refusal
(the state is unchanged); the grid is one step per cell.

`Env` is a record of functions; the driver builds it from finite decision
tables and emits the tables. A `duplicityAt` row selects the concrete
partial/augmented fixture in `DuplicityExamples`; it is not a Boolean
oracle. The separate `duplicity` cases emit complete evidence and verdicts.
`consumableStateB`, the model's own decidable mirror of
`consumableState` (tied to it by `consumableStateB_iff`), is emitted for
the grid states at `bornAt + W − 1 / = / + 1` so the JavaScript consumer
agrees with the model's by hash.

Local states are absent, present (live, poisoned, frozen), retained parked,
termination pending and convicted. Only an associated system completion
retires a pending identity; no local action performs that transition.
-/

open Lean (ToJson toJson Json FromJson fromJson?)
open CardanoKeri.Checkpoint
open CardanoKeri.Checkpoint.TraceWire

/-- The deployment used everywhere: `D` = 1000, `B` = 5, `P` = 2, `W` = 10. -/
def params : Params := { D := 1000, B := 5, P := 2, W := 10, hD := by decide, hB := by decide }

/-- One step record: the input state, the slot, the action, and the result
(`null` when `stepFn` refuses). -/
def stepJson (p : Params) (env : Env) (now : Slot) (s : State) (a : Action) : Json × State :=
  match stepFn p env a now s with
  | some (f, s') =>
      (Json.mkObj [("now", toJson now), ("input", toJson s), ("action", toJson a),
        ("result", Json.mkObj [("flow", toJson f), ("state", toJson s')])], s')
  | none =>
      (Json.mkObj [("now", toJson now), ("input", toJson s), ("action", toJson a), ("result", Json.null)], s)

/-- Fold a seeded trace: refused steps are recorded and the state kept. -/
def runTrace (p : Params) (env : Env) : State → List (Slot × Action) → List Json
  | _, [] => []
  | s, (t, a) :: rest =>
      let (j, s') := stepJson p env t s a
      j :: runTrace p env s' rest

structure Seed where
  name : String
  env : EnvTable
  steps : List (Slot × Action)

/-- Alice = 1, Hal = 2, Cora = 3, Mallory = 4, the treasury = 5, the sponsor = 6, a rival = 7. -/
def seeds : List Seed := [
  { name := "happy-path",
    env := { rotationTo := [(0, 0, 1), (1, 1, 2)], intentAuthorized := [(1, .keep, some 1)], quorum := [], duplicityAt := [] },
    steps := [(0, .register 6 10), (12, .rotate 1 .keep 2 (some 1)), (12, .rotate 1 .keep 2 none),
              (20, .topUp 5), (25, .rotate 2 .keep 2 none)] },
  { name := "freeze-then-unfreeze",
    env := { rotationTo := [(0, 0, 1), (1, 1, 2)], intentAuthorized := [(1, .deposit, none), (2, .deposit, none)], quorum := [], duplicityAt := [] },
    steps := [(0, .register 1 1), (12, .freeze 1 2), (12, .freeze 1 2), (20, .rotate 1 .deposit 1 none),
              (20, .topUp 20), (25, .rotate 2 .deposit 1 none)] },
  { name := "close-then-revive",
    env := { rotationTo := [(0, 0, 1), (1, 1, 2)], intentAuthorized := [(1, .close 1, none)], quorum := [0, 1], duplicityAt := [] },
    steps := [(0, .register 1 10), (12, .close 1 1 none), (12, .close 2 1 none), (12, .poison),
              (12, .freeze 2 2), (12, .topUp 3), (12, .register 1 10), (40, .reopen 1 1 5), (40, .reopen 2 1 5), (40, .topUp 3)] },
  { name := "poison-then-close-then-reopen",
    env := { rotationTo := [(0, 0, 1), (1, 1, 2)], intentAuthorized := [(1, .close 2, none)], quorum := [0], duplicityAt := [] },
    steps := [(0, .register 1 1), (12, .poison), (12, .poison), (12, .freeze 1 2), (12, .topUp 5),
              (12, .close 1 2 none), (12, .topUp 1), (12, .rotate 2 .keep 2 none), (12, .reopen 1 1 5), (30, .reopen 2 1 5),
              (30, .topUp 1)] },
  { name := "convict",
    env := { rotationTo := [(0, 0, 1)], intentAuthorized := [], quorum := [1], duplicityAt := [(1, 1)] },
    steps := [(0, .register 1 12), (12, .rotate 1 .keep 2 none), (12, .convict 3), (12, .rotate 1 .deposit 1 none), (12, .close 1 1 none),
              (12, .topUp 1), (12, .register 1 10), (12, .reopen 1 1 10)] },
  { name := "convict-parked",
    env := { rotationTo := [(0, 0, 1), (1, 1, 2)], intentAuthorized := [(1, .close 1, none)], quorum := [], duplicityAt := [(1, 1)] },
    steps := [(0, .register 1 10), (12, .close 1 1 none), (12, .convict 3), (12, .reopen 2 1 10), (12, .convict 3)] },
  { name := "relayer-on-public-data",
    env := { rotationTo := [(0, 0, 1)], intentAuthorized := [], quorum := [0, 1], duplicityAt := [] },
    steps := [(0, .register 1 10), (12, .rotate 1 .deposit 2 none), (12, .close 1 2 none),
              (12, .rotate 1 .keep 2 (some 9)), (12, .rotate 1 .keep 2 none), (12, .close 1 2 none)] },
  { name := "copied-reap",
    env := { rotationTo := [(0, 0, 1)], intentAuthorized := [(1, .close 2, none)], quorum := [], duplicityAt := [] },
    steps := [(0, .register 1 10), (12, .close 1 9 none), (12, .close 1 2 (some 9)), (12, .close 1 2 none), (12, .reopen 2 1 10)] }
]

def traceJson (p : Params) (sd : Seed) : Json :=
  Json.mkObj [("name", toJson sd.name), ("env", toJson sd.env), ("initial", toJson State.absent),
    ("steps", Json.arr (runTrace p sd.env.toEnv .absent sd.steps).toArray)]

/-- Index a list from 0. -/
def enumL (l : List α) : List (Nat × α) := (List.range l.length).zip l

/-! ## The boundary grid: every guarded comparison at −1 / = / +1, every action, every state -/

/-- Present states around the guards: `poisoned` and `frozen` both ways;
`pool` at one below, exactly, one above the premium. The base datum is at
epoch 1, sequence 1, born at 10, refund address 1. -/
def gridPresent (p : Params) : List State :=
  let vals := fun (x : Nat) => [x - 1, x, x + 1]
  [false, true].flatMap fun poisoned =>
    [false, true].flatMap fun frozen =>
      (vals p.P).map fun pool =>
        State.present ⟨1, 1, poisoned, frozen, 10, 1, pool⟩

def gridStates (p : Params) : List State :=
  [.absent, .parked ⟨1, 1⟩, .terminationPending ⟨1, 1⟩, .convicted] ++ gridPresent p

/-- Actions with their sequence at −1 / = / +1 of the datum's (1), both bond
options, the refund option none / authorized (1) / unauthorized (9); the close
with the same sequences, the signed payee (2) and a copied payee (9), and the
same refund options; the reopen at −1 / = / +1 of the parked sequence (1). -/
def gridActions : List Action :=
  [.register 6 7, .poison, .topUp 5, .convict 3] ++
  ([0, 1, 2].map fun sn' => Action.freeze sn' 2) ++
  ([0, 1, 2].flatMap fun sn' =>
    [BondOp.keep, .deposit].flatMap fun op =>
      [none, some 1, some 9].map fun r => Action.rotate sn' op 2 r) ++
  ([0, 1, 2].flatMap fun sn' => [2, 9].flatMap fun payee => [none, some 1, some 9].map fun r => Action.close sn' payee r) ++
  ([0, 1, 2].map fun sn' => Action.reopen sn' 1 7)

/-- Two oracles: everything the grid can ask for (one close message: payee 2), and nothing. -/
def gridEnvs : List (String × EnvTable) :=
  [("full", { rotationTo := [(1, 1, 0), (1, 1, 1), (1, 1, 2)],
              intentAuthorized := [(2, .keep, some 1), (2, .deposit, none), (2, .deposit, some 1), (2, .close 2, none), (2, .close 2, some 1)],
              quorum := [1], duplicityAt := [(1, 1)] }),
   ("none", { rotationTo := [], intentAuthorized := [], quorum := [], duplicityAt := [] })]

/-- The grid at slot 20, as cells referencing the state, action and env
tables by index; a refused cell has `result: null`. -/
def gridJson (p : Params) : Json :=
  let states := gridStates p
  let now : Slot := 20
  let cells : List Json :=
    (enumL states).flatMap fun (si, s) =>
      (enumL gridActions).flatMap fun (ai, a) =>
        (enumL gridEnvs).map fun (ei, (_, t)) =>
          let (j, _) := stepJson p t.toEnv now s a
          Json.mkObj [("s", toJson si), ("a", toJson ai), ("e", toJson ei),
            ("result", (j.getObjVal? "result").toOption.getD Json.null)]
  -- consumability at bornAt + W − 1 / = / + 1 for every grid state
  let cons : List Json :=
    (enumL states).flatMap fun (si, s) =>
      [10 + p.W - 1, 10 + p.W, 10 + p.W + 1].map fun t =>
        Json.mkObj [("s", toJson si), ("now", toJson t), ("consumable", toJson (consumableStateB p t s))]
  Json.mkObj [("now", toJson now), ("states", toJson states), ("actions", toJson gridActions),
    ("envs", toJson (gridEnvs.map (·.2))), ("cells", Json.arr cells.toArray), ("consumable", Json.arr cons.toArray)]

/-! ## Story cells: Lean's verdict on every step of the fifteen scenario files

The scenario files are the simulator's; the driver folds each one exactly as
the JavaScript session does (per-step params, seeds, evidence rows, the slot
guard) and asks `stepFn` at every action. A step whose parameters cannot be a
`Params` (a zero bond) or whose slot goes backwards has no cell: the Lean has
nothing to say there, and the simulator's T7 is not shown on it. -/

structure StoryFold where
  params : Params
  env : EnvTable
  state : State
  now : Slot
  cells : List Json

def storyStep (f : StoryFold) (idx : Json) (st : Json) : Except String StoryFold := do
  let slot ← st.getObjValAs? Nat "slot"
  -- this step's parameters: an override applies to this step only
  let stepParams : Option Params := match st.getObjVal? "params" with
    | .ok pj => (paramsOfJson pj).toOption
    | .error _ => some f.params
  let state := match st.getObjVal? "seed" with
    | .ok sj => match (fromJson? sj : Except String State) with | .ok s => s | .error _ => f.state
    | .error _ => f.state
  let mut env := f.env
  match st.getObjVal? "evidence" with
  | .ok ev =>
    match ev.getObjVal? "remove" with
    | .ok (Json.arr rows) => for r in rows do env ← env.applyRow false r
    | _ => pure ()
    match ev.getObjVal? "add" with
    | .ok (Json.arr rows) => for r in rows do env ← env.applyRow true r
    | _ => pure ()
  | .error _ => pure ()
  match st.getObjVal? "action" with
  | .error _ =>
    pure { f with env, state, now := if f.now ≤ slot then slot else f.now }
  | .ok aj =>
    if slot < f.now then pure { f with env, state }   -- slot regression: no cell, nothing moves
    else
      match (fromJson? aj : Except String Action), stepParams with
      | .error _, _ => pure { f with env, state, now := slot }   -- not a Lean Action (unknown redeemer, non-Nat field): no cell
      | .ok _, none => pure { f with env, state, now := slot }   -- no Params: no cell
      | .ok action, some p =>
        let (j, state') := stepJson p env.toEnv slot state action
        let cell := Json.mkObj [("index", idx), ("params", toJson p), ("env", toJson env),
          ("now", toJson slot), ("input", toJson state), ("action", toJson action),
          ("result", (j.getObjVal? "result").toOption.getD Json.null)]
        pure { f with env, state := state', now := slot, cells := f.cells ++ [cell] }

/-- Fold a branch: every step in order, indexed by `idx`. -/
def foldSteps (f : StoryFold) (steps : List Json) (idx : Nat → Json) : Except String StoryFold := do
  let mut f := f
  let mut i := 0
  for st in steps do
    f ← storyStep f (idx i) st
    i := i + 1
  pure f

/-- A scenario is a tree: the trunk (`steps`) and its forks (`forks`, each
departing after trunk step `at`). Every branch is folded from the origin, so a
fork's cells carry the trunk prefix's state; fork cells are indexed
`f<id>.<i>`. -/
def storyJson (sc : Json) : Except String Json := do
  let story ← sc.getObjValAs? Nat "story"
  let p ← paramsOfJson (← sc.getObjVal? "params")
  let steps ← (← sc.getObjVal? "steps").getArr?
  let init : StoryFold := ⟨p, ⟨[], [], [], []⟩, .absent, 0, []⟩
  let trunk ← foldSteps init steps.toList (fun i => toJson i)
  let forks := match sc.getObjVal? "forks" with
    | .ok (Json.arr fs) => fs.toList
    | _ => []
  let mut cells := trunk.cells
  for fk in forks do
    let departsAfter ← fk.getObjValAs? Nat "at"
    let fsteps ← (← fk.getObjVal? "steps").getArr?
    let id := (fk.getObjValAs? String "id").toOption.getD "?"
    let prefixFold ← foldSteps init (steps.toList.take (departsAfter + 1)) (fun i => toJson i)
    let branch ← foldSteps { prefixFold with cells := [] } fsteps.toList (fun i => Json.str s!"f{id}.{i}")
    cells := cells ++ branch.cells
  pure (Json.mkObj [("story", toJson story), ("steps", Json.arr cells.toArray)])

def readScenarios : IO (List Json) := do
  let dir : System.FilePath := "../simulator/checkpoint-simulator-scenarios"
  let entries ← dir.readDir
  let names := (entries.map (·.fileName)).filter (·.endsWith ".json") |>.qsort (· < ·)
  names.toList.mapM fun n => do
    let txt ← IO.FS.readFile (dir / System.FilePath.mk n)
    match Json.parse txt with
    | .ok j => pure j
    | .error e => throw (IO.userError s!"{n}: {e}")

#eval do
  let scs ← readScenarios
  let stories ← scs.mapM fun sc => match storyJson sc with
    | .ok j => pure j
    | .error e => throw (IO.userError s!"story fold failed: {e}")
  IO.println (Json.mkObj [
    ("schema", "cardano-keri.checkpoint-trace"), ("version", (2 : Nat)), ("params", toJson params),
    ("traces", Json.arr (seeds.map (traceJson params)).toArray),
    ("grid", gridJson params),
    ("duplicity", Lean.toJson (CardanoKeri.Duplicity.scenarios.map CardanoKeri.Duplicity.scenarioJson)),
    ("stories", Json.arr stories.toArray)]).compress
