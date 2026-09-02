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

open Lean (ToJson toJson Json)
open CardanoKeri.Checkpoint

deriving instance Lean.ToJson for BondOp
deriving instance Lean.ToJson for Action
deriving instance Lean.ToJson for Live
deriving instance Lean.ToJson for State
deriving instance Lean.ToJson for Payment
deriving instance Lean.ToJson for Flow

/-- `Params` carries two proofs, so its instance is written by hand. -/
instance : ToJson Params where
  toJson p := Json.mkObj [("D", toJson p.D), ("B", toJson p.B), ("P", toJson p.P), ("W", toJson p.W)]

/-- Finite decision tables standing for the four evidence predicates. -/
structure EnvTable where
  rotationTo : List (Nat × Nat × Nat)
  refundAuthorized : List (Nat × Nat)
  quorum : List Nat
  duplicityAt : List (Nat × Nat)

def EnvTable.toEnv (t : EnvTable) : Env where
  rotationTo := fun e sn sn' => t.rotationTo.contains (e, sn, sn')
  refundAuthorized := fun e a => t.refundAuthorized.contains (e, a)
  quorum := fun e => t.quorum.contains e
  duplicityAt := fun e sn => t.duplicityAt.contains (e, sn)

instance : ToJson EnvTable where
  toJson t := Json.mkObj [
    ("rotationTo", toJson (t.rotationTo.map fun (e, sn, sn') => [e, sn, sn'])),
    ("refundAuthorized", toJson (t.refundAuthorized.map fun (e, a) => [e, a])),
    ("quorum", toJson (t.quorum.map fun e => [e])),
    ("duplicityAt", toJson (t.duplicityAt.map fun (e, sn) => [e, sn]))]

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

/-- Alice = 1, Hal = 2, Cora = 3, Mallory = 4, the treasury = 5, a friend = 6. -/
def seeds : List Seed := [
  { name := "happy-path",
    env := { rotationTo := [(0, 0, 1), (1, 1, 2)], refundAuthorized := [(1, 1)], quorum := [], duplicityAt := [] },
    steps := [(0, .register 6 10), (12, .rotate 1 .keep 2 (some 1)), (12, .rotate 1 .keep 2 none),
              (20, .topUp 5), (25, .rotate 2 .keep 2 none)] },
  { name := "freeze-then-unfreeze",
    env := { rotationTo := [(0, 0, 1)], refundAuthorized := [], quorum := [], duplicityAt := [] },
    steps := [(0, .register 1 1), (12, .freeze 1 2), (12, .freeze 1 2), (20, .rotate 1 .deposit 1 none),
              (20, .topUp 20)] },
  { name := "pause-then-resurrect",
    env := { rotationTo := [(0, 0, 1), (1, 1, 2)], refundAuthorized := [], quorum := [0], duplicityAt := [] },
    steps := [(0, .register 1 10), (12, .rotate 1 .withdraw 1 none), (12, .close), (12, .poison),
              (12, .freeze 2 2), (12, .topUp 3), (40, .rotate 2 .deposit 1 none)] },
  { name := "poison-then-rotate",
    env := { rotationTo := [(0, 0, 1)], refundAuthorized := [], quorum := [0], duplicityAt := [] },
    steps := [(0, .register 1 1), (12, .poison), (12, .poison), (12, .close), (12, .freeze 1 2),
              (12, .topUp 5), (12, .rotate 1 .keep 2 none), (12, .close)] },
  { name := "convict",
    env := { rotationTo := [(0, 0, 1)], refundAuthorized := [], quorum := [0], duplicityAt := [(0, 0)] },
    steps := [(0, .register 1 10), (12, .convict 3), (12, .rotate 1 .deposit 1 none), (12, .close),
              (12, .topUp 1), (12, .register 1 10)] },
  { name := "close",
    env := { rotationTo := [(0, 0, 1)], refundAuthorized := [(1, 1)], quorum := [0, 1], duplicityAt := [] },
    steps := [(0, .register 6 10), (12, .poison), (12, .close), (20, .rotate 1 .keep 2 (some 1)), (20, .close),
              (20, .register 1 10), (20, .topUp 1)] }
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
  [.absent, .gone, .convicted 1 1 10] ++ gridPresent p

/-- Actions with their sequence at −1 / = / +1 of the datum's (1), every bond
option, the refund option none / authorized (1) / unauthorized (9). -/
def gridActions : List Action :=
  [.register 6 7, .poison, .topUp 5, .convict 3, .close] ++
  ([0, 1, 2].map fun sn' => Action.freeze sn' 2) ++
  ([0, 1, 2].flatMap fun sn' =>
    [BondOp.keep, .withdraw, .deposit].flatMap fun op =>
      [none, some 1, some 9].map fun r => Action.rotate sn' op 2 r)

/-- Two oracles: everything the grid can ask for, and nothing. -/
def gridEnvs : List (String × EnvTable) :=
  [("full", { rotationTo := [(1, 1, 0), (1, 1, 1), (1, 1, 2)], refundAuthorized := [(2, 1)], quorum := [1], duplicityAt := [(1, 1)] }),
   ("none", { rotationTo := [], refundAuthorized := [], quorum := [], duplicityAt := [] })]

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

#eval IO.println (Json.mkObj [
  ("schema", "cardano-keri.checkpoint-trace"), ("version", (1 : Nat)), ("params", toJson params),
  ("traces", Json.arr (seeds.map (traceJson params)).toArray),
  ("grid", gridJson params)]).compress
