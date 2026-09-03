import Lean
import CardanoKeri.Checkpoint

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
tables and emits the tables, so the JavaScript core evaluates the same
oracle. `consumableState` is a `Prop` with no executable form in the model;
`consumableB` below is the driver's Bool transcription, emitted for the grid
states at `bornAt + W − 1 / = / + 1` so the two transcriptions (Lean-side
and JavaScript-side) at least agree by hash.
-/

open Lean (ToJson toJson Json FromJson fromJson?)
open CardanoKeri.Checkpoint

deriving instance Lean.ToJson for BondOp
deriving instance Lean.ToJson for Intent
deriving instance Lean.ToJson for Action
deriving instance Lean.ToJson for Live
deriving instance Lean.ToJson for State
deriving instance Lean.ToJson for Payment
deriving instance Lean.ToJson for Flow
deriving instance Lean.FromJson for BondOp
deriving instance Lean.FromJson for Intent
deriving instance Lean.FromJson for Action
deriving instance Lean.FromJson for Live
deriving instance Lean.FromJson for State

/-- `Params` carries two proofs, so its instance is written by hand. -/
instance : ToJson Params where
  toJson p := Json.mkObj [("D", toJson p.D), ("B", toJson p.B), ("P", toJson p.P), ("W", toJson p.W)]

/-- `Params` from JSON, with the two positivity proofs decided at parse time:
a deployment with a zero bond has no `Params` and therefore no Lean cell. -/
def paramsOfJson (j : Json) : Except String Params := do
  let D ← j.getObjValAs? Nat "D"
  let B ← j.getObjValAs? Nat "B"
  let P ← j.getObjValAs? Nat "P"
  let W ← j.getObjValAs? Nat "W"
  if hD : 0 < D then
    if hB : 0 < B then pure { D, B, P, W, hD, hB }
    else throw "B must be positive"
  else throw "D must be positive"

/-- Finite decision tables standing for the four evidence predicates. -/
structure EnvTable where
  rotationTo : List (Nat × Nat × Nat)
  /-- `(e, intent, refund address or none)`: the keys of epoch `e` signed that intent message (D-038). -/
  intentAuthorized : List (Nat × Intent × Option Nat)
  quorum : List Nat
  duplicityAt : List (Nat × Nat)

def EnvTable.toEnv (t : EnvTable) : Env where
  rotationTo := fun e sn sn' => t.rotationTo.contains (e, sn, sn')
  intentAuthorized := fun e i r => t.intentAuthorized.contains (e, i, r)
  quorum := fun e => t.quorum.contains e
  duplicityAt := fun e sn => t.duplicityAt.contains (e, sn)

instance : ToJson EnvTable where
  toJson t := Json.mkObj [
    ("rotationTo", toJson (t.rotationTo.map fun (e, sn, sn') => [e, sn, sn'])),
    ("intentAuthorized", Json.arr (t.intentAuthorized.map fun (e, i, r) => Json.arr #[toJson e, toJson i, toJson r]).toArray),
    ("quorum", toJson (t.quorum.map fun e => [e])),
    ("duplicityAt", toJson (t.duplicityAt.map fun (e, sn) => [e, sn]))]

/-- An evidence row `{kind: [args]}` of a scenario file, added to or removed from a table. -/
def EnvTable.applyRow (t : EnvTable) (add : Bool) (row : Json) : Except String EnvTable := do
  let upd {α} [BEq α] (l : List α) (x : α) : List α := if add then (if l.contains x then l else l ++ [x]) else l.filter (· != x)
  let nats (v : Json) : Except String (List Nat) := fromJson? v
  match row.getObjVal? "rotationTo" with
  | .ok v =>
    let l ← nats v
    match l with
    | [e, sn, sn'] => pure { t with rotationTo := upd t.rotationTo (e, sn, sn') }
    | _ => throw "rotationTo row needs three numbers"
  | .error _ =>
  match row.getObjVal? "intentAuthorized" with
  | .ok v =>
    match v.getArr? with
    | .ok #[ej, ij, rj] =>
      let e : Nat ← fromJson? ej
      let i : Intent ← fromJson? ij
      let r : Option Nat ← if rj.isNull then pure none else (fromJson? rj : Except String Nat).map some
      pure { t with intentAuthorized := upd t.intentAuthorized (e, i, r) }
    | _ => throw "intentAuthorized row needs [epoch, intent, address or null]"
  | .error _ =>
  match row.getObjVal? "quorum" with
  | .ok v =>
    let l ← nats v
    match l with
    | [e] => pure { t with quorum := upd t.quorum e }
    | _ => throw "quorum row needs one number"
  | .error _ =>
  match row.getObjVal? "duplicityAt" with
  | .ok v =>
    let l ← nats v
    match l with
    | [e, sn] => pure { t with duplicityAt := upd t.duplicityAt (e, sn) }
    | _ => throw "duplicityAt row needs two numbers"
  | .error _ => throw "unknown evidence row"

/-- The deployment used everywhere: `D` = 1000, `B` = 5, `P` = 2, `W` = 10. -/
def params : Params := { D := 1000, B := 5, P := 2, W := 10, hD := by decide, hB := by decide }

/-- Bool transcription of `consumableState` (a `Prop` in the model). -/
def consumableB (p : Params) (now : Slot) : State → Bool
  | .present l => l.dreg == p.D && l.b == p.B && l.poisoned == false && decide (l.bornAt + p.W ≤ now)
  | _ => false

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

/-- Alice = 1, Hal = 2, Cora = 3, Mallory = 4, the treasury = 5, the sponsor = 6. -/
def seeds : List Seed := [
  { name := "happy-path",
    env := { rotationTo := [(0, 0, 1), (1, 1, 2)], intentAuthorized := [(1, .keep, some 1)], quorum := [], duplicityAt := [] },
    steps := [(0, .register 6 10), (12, .rotate 1 .keep 2 (some 1)), (12, .rotate 1 .keep 2 none),
              (20, .topUp 5), (25, .rotate 2 .keep 2 none)] },
  { name := "freeze-then-unfreeze",
    env := { rotationTo := [(0, 0, 1)], intentAuthorized := [(1, .deposit, none)], quorum := [], duplicityAt := [] },
    steps := [(0, .register 1 1), (12, .freeze 1 2), (12, .freeze 1 2), (20, .rotate 1 .deposit 1 none),
              (20, .topUp 20)] },
  { name := "pause-then-resurrect",
    env := { rotationTo := [(0, 0, 1), (1, 1, 2)], intentAuthorized := [(1, .withdraw, none), (2, .deposit, none)], quorum := [0], duplicityAt := [] },
    steps := [(0, .register 1 10), (12, .rotate 1 .withdraw 1 none), (12, .close 2 none), (12, .poison),
              (12, .freeze 2 2), (12, .topUp 3), (40, .rotate 2 .deposit 1 none)] },
  { name := "poison-then-close-then-reopen",
    env := { rotationTo := [(0, 0, 1), (1, 1, 2)], intentAuthorized := [(1, .close, none)], quorum := [0], duplicityAt := [] },
    steps := [(0, .register 1 1), (12, .poison), (12, .poison), (12, .freeze 1 2), (12, .topUp 5),
              (12, .close 1 none), (12, .topUp 1), (12, .rotate 2 .keep 2 none), (12, .reopen 1 1 5), (30, .reopen 2 1 5),
              (30, .topUp 1)] },
  { name := "convict",
    env := { rotationTo := [(0, 0, 1)], intentAuthorized := [], quorum := [0], duplicityAt := [(0, 0)] },
    steps := [(0, .register 1 10), (12, .convict 3), (12, .rotate 1 .deposit 1 none), (12, .close 1 none),
              (12, .topUp 1), (12, .register 1 10), (12, .reopen 1 1 10)] },
  { name := "relayer-on-public-data",
    env := { rotationTo := [(0, 0, 1)], intentAuthorized := [], quorum := [0, 1], duplicityAt := [] },
    steps := [(0, .register 1 10), (12, .rotate 1 .withdraw 2 none), (12, .rotate 1 .deposit 2 none), (12, .close 1 none),
              (12, .rotate 1 .keep 2 (some 9)), (12, .rotate 1 .keep 2 none), (12, .close 1 none)] },
  { name := "close-then-reopen",
    env := { rotationTo := [(0, 0, 1), (1, 1, 2), (2, 2, 3)], intentAuthorized := [(1, .close, some 1), (1, .keep, some 1)], quorum := [0, 1], duplicityAt := [] },
    steps := [(0, .register 6 10), (12, .poison), (12, .close 1 (some 1)), (20, .reopen 1 1 10), (20, .reopen 2 1 10),
              (20, .register 1 10), (20, .topUp 1), (20, .rotate 3 .keep 2 none)] }
]

def traceJson (p : Params) (sd : Seed) : Json :=
  Json.mkObj [("name", toJson sd.name), ("env", toJson sd.env), ("initial", toJson State.absent),
    ("steps", Json.arr (runTrace p sd.env.toEnv .absent sd.steps).toArray)]

/-- Index a list from 0. -/
def enumL (l : List α) : List (Nat × α) := (List.range l.length).zip l

/-! ## The boundary grid: every guarded comparison at −1 / = / +1, every action, every state -/

/-- Present states around the guards: `poisoned` both ways; `dreg`, `b`,
`pool` at one below, exactly, one above the parameter. The base datum is at
epoch 1, sequence 1, born at 10, refund address 1. -/
def gridPresent (p : Params) : List State :=
  let vals := fun (x : Nat) => [x - 1, x, x + 1]
  [false, true].flatMap fun poisoned =>
    (vals p.D).flatMap fun dreg =>
      (vals p.B).flatMap fun b =>
        (vals p.P).map fun pool =>
          State.present ⟨1, 1, poisoned, 10, 1, dreg, b, pool⟩

def gridStates (p : Params) : List State :=
  [.absent, .closed 1 1, .convicted 1 1 10] ++ gridPresent p

/-- Actions with their sequence at −1 / = / +1 of the datum's (1), every bond
option, the refund option none / authorized (1) / unauthorized (9); the close
with the same sequences and refund options; the reopen at −1 / = / +1 of the
tombstone's sequence (1). -/
def gridActions : List Action :=
  [.register 6 7, .poison, .topUp 5, .convict 3] ++
  ([0, 1, 2].map fun sn' => Action.freeze sn' 2) ++
  ([0, 1, 2].flatMap fun sn' =>
    [BondOp.keep, .withdraw, .deposit].flatMap fun op =>
      [none, some 1, some 9].map fun r => Action.rotate sn' op 2 r) ++
  ([0, 1, 2].flatMap fun sn' => [none, some 1, some 9].map fun r => Action.close sn' r) ++
  ([0, 1, 2].map fun sn' => Action.reopen sn' 1 7)

/-- Two oracles: everything the grid can ask for, and nothing. -/
def gridEnvs : List (String × EnvTable) :=
  [("full", { rotationTo := [(1, 1, 0), (1, 1, 1), (1, 1, 2)],
              intentAuthorized := [(2, .keep, some 1), (2, .withdraw, none), (2, .withdraw, some 1), (2, .deposit, none), (2, .deposit, some 1), (2, .close, none), (2, .close, some 1)],
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
        Json.mkObj [("s", toJson si), ("now", toJson t), ("consumable", toJson (consumableB p t s))]
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
    ("schema", "cardano-keri.checkpoint-trace"), ("version", (1 : Nat)), ("params", toJson params),
    ("traces", Json.arr (seeds.map (traceJson params)).toArray),
    ("grid", gridJson params),
    ("stories", Json.arr stories.toArray)]).compress
