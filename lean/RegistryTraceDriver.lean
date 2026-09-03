import Lean
import CardanoKeri.Registry

/-!
# The registry — trace interchange v2 producer

Emits the `cardano-keri.registry.trace` version-2 corpus embedded by
`simulator/registry-simulator.html`: `Sys`, `Action`, `Flow` and `Params` are
serialized by hand-written `ToJson` instances over the authoritative
`stepFn` of `CardanoKeri.Registry`. Every cell carries its explicit input
state, the slot, the action, and the result (`null` when `stepFn` refuses;
otherwise the `Flow` and the post-state).

Three families of cells: six **seeded traces**; a **boundary grid** (two
systems × every action shape at every guard's −1 / = / +1 × two evidence
oracles); the **story cells** of the fifteen scenario files.

Reproducible from a clean checkout with

```sh
cd lean && nix shell nixpkgs#lean4 -c lake build CardanoKeri.Registry
cd lean && nix shell nixpkgs#lean4 -c lake env lean RegistryTraceDriver.lean
```
-/

open Lean (ToJson toJson Json FromJson fromJson?)

namespace CardanoKeri.Registry.TraceDriver

/-! ## Wire serialization -/

instance : ToJson Params where
  toJson p := Json.mkObj [("D", toJson p.D), ("tip", toJson p.tip), ("Mc", toJson p.Mc), ("Mr", toJson p.Mr),
    ("process", toJson p.process), ("retract", toJson p.retract), ("W", toJson p.W), ("far", toJson p.far)]

instance : ToJson Status where
  toJson
    | .active tok => Json.mkObj [("active", toJson tok)]
    | .dormant k => Json.mkObj [("dormant", toJson k)]
    | .convicted => Json.str "convicted"

instance : ToJson CkState where
  toJson
    | .live => Json.str "live"
    | .parked since => Json.mkObj [("parked", toJson since)]
    | .tomb => Json.str "tomb"

instance : ToJson Ckpt where
  toJson c := Json.mkObj [("token", toJson c.token), ("k", toJson c.k), ("st", toJson c.st)]

instance : ToJson Op where
  toJson
    | .register => Json.str "register"
    | .revive => Json.str "revive"
    | .goDormant k => Json.mkObj [("goDormant", toJson k)]
    | .goConvicted => Json.str "goConvicted"
    | .convict => Json.str "convict"

private def requestJson (id : ReqId) (r : Request) : Json :=
  Json.mkObj [("id", toJson id), ("aid", toJson r.aid), ("owner", toJson r.owner),
              ("submittedAt", toJson r.submittedAt), ("op", toJson r.op)]

instance : ToJson Sys where
  toJson s := Json.mkObj [("gen", toJson s.gen), ("plugin", toJson s.plugin),
    ("leaves", Json.arr (s.leaves.map fun (a, v) => Json.mkObj [("aid", toJson a), ("status", toJson v)]).toArray),
    ("ckpts", Json.arr (s.ckpts.map fun (a, c) => Json.mkObj [("aid", toJson a), ("ckpt", toJson c)]).toArray),
    ("requests", Json.arr (s.requests.map fun (id, r) => requestJson id r).toArray),
    ("nextReq", toJson s.nextReq), ("nextToken", toJson s.nextToken)]

private def foldActionJson : FoldAction → Json
  | .process => Json.str "process"
  | .reject => Json.str "reject"

instance : ToJson Action where
  toJson
    | .contribute aid owner t op => Json.mkObj [("contribute", Json.mkObj
        [("aid", toJson aid), ("owner", toJson owner), ("submittedAt", toJson t), ("op", toJson op)])]
    | .fold folder g pl batch => Json.mkObj [("fold", Json.mkObj
        [("folder", toJson folder), ("gen", toJson g), ("plugin", toJson pl),
         ("batch", Json.arr (batch.map fun (id, fa) =>
            Json.mkObj [("id", toJson id), ("do", foldActionJson fa)]).toArray)])]
    | .retract id => Json.mkObj [("retract", Json.mkObj [("req", toJson id)])]
    | .reap reaper aid => Json.mkObj [("reap", Json.mkObj [("reaper", toJson reaper), ("aid", toJson aid)])]
    | .pause aid => Json.mkObj [("pause", Json.mkObj [("aid", toJson aid)])]
    | .resume aid => Json.mkObj [("resume", Json.mkObj [("aid", toJson aid)])]
    | .convictCkpt aid => Json.mkObj [("convictCkpt", Json.mkObj [("aid", toJson aid)])]

private def pairJson (a v : Nat) (ka kv : String) : Json := Json.mkObj [(ka, toJson a), (kv, toJson v)]

instance : ToJson Flow where
  toJson f := Json.mkObj [("deposited", toJson f.deposited),
    ("locked", Json.arr (f.locked.map fun (aid, v) => pairJson aid v "aid" "value").toArray),
    ("refunds", Json.arr (f.refunds.map fun (a, v) => pairJson a v "addr" "value").toArray),
    ("tips", match f.tips with | some (a, v) => pairJson a v "addr" "value" | none => Json.null),
    ("premium", match f.premium with | some (a, v) => pairJson a v "addr" "value" | none => Json.null),
    ("intoRequest", toJson f.intoRequest)]

/-- An evidence table. -/
structure EnvTable where
  inception : List AID
  rotationFrom : List (AID × KeyState)
  duplicity : List (AID × KeyState)
  quorum : List AID

def EnvTable.toEnv (t : EnvTable) : Env :=
  { inception := fun a => t.inception.contains a,
    rotationFrom := fun a k => t.rotationFrom.contains (a, k),
    duplicity := fun a k => t.duplicity.contains (a, k),
    quorum := fun a => t.quorum.contains a }

instance : ToJson EnvTable where
  toJson t := Json.mkObj [("inception", toJson t.inception),
    ("rotationFrom", toJson (t.rotationFrom.map fun (a, k) => [a, k])),
    ("duplicity", toJson (t.duplicity.map fun (a, k) => [a, k])),
    ("quorum", toJson t.quorum)]

/-! ## Parsing the scenario files -/

def natList (j : Json) : Except String (List Nat) := fromJson? j

def pairList (j : Json) : Except String (List (Nat × Nat)) := do
  let rows ← j.getArr?
  rows.toList.mapM fun r => do
    match ← natList r with
    | [a, b] => pure (a, b)
    | _ => throw "evidence row needs two numbers"

def envOfJson (j : Json) : Except String EnvTable := do
  let get1 (k : String) : Except String (List Nat) := match j.getObjVal? k with
    | .ok v => natList v
    | .error _ => pure []
  let get2 (k : String) : Except String (List (Nat × Nat)) := match j.getObjVal? k with
    | .ok v => pairList v
    | .error _ => pure []
  pure ⟨← get1 "inception", ← get2 "rotationFrom", ← get2 "duplicity", ← get1 "quorum"⟩

def paramsOfJson (j : Json) : Except String Params := do
  let D ← j.getObjValAs? Nat "D"
  let tip ← j.getObjValAs? Nat "tip"
  let Mc ← j.getObjValAs? Nat "Mc"
  let Mr ← j.getObjValAs? Nat "Mr"
  let process ← j.getObjValAs? Nat "process"
  let retract ← j.getObjValAs? Nat "retract"
  let W ← j.getObjValAs? Nat "W"
  let far ← j.getObjValAs? Nat "far"
  if hD : 0 < D then
    if hP : 0 < process then
      if hR : 0 < retract then
        if hF : Mr + tip ≤ Mc then
          pure { D, tip, Mc, Mr, process, retract, W, far, hD, hProcess := hP, hRetract := hR, hFund := hF }
        else throw "Mr + tip must not exceed Mc"
      else throw "retract must be positive"
    else throw "process must be positive"
  else throw "D must be positive"

def opOfJson (j : Json) : Except String Op := do
  match j.getStr? with
  | .ok "register" => pure .register
  | .ok "revive" => pure .revive
  | .ok "goConvicted" => pure .goConvicted
  | .ok "convict" => pure .convict
  | .ok s => throw s!"unknown op {s}"
  | .error _ =>
    match j.getObjVal? "goDormant" with
    | .ok k => pure (.goDormant (← fromJson? k))
    | .error _ => throw "unknown op"

def foldActionOfJson (j : Json) : Except String FoldAction := do
  match ← j.getStr? with
  | "process" => pure .process
  | "reject" => pure .reject
  | s => throw s!"unknown fold action {s}"

def actionOfJson (j : Json) : Except String Action := do
  match j.getObjVal? "contribute" with
  | .ok c => pure (.contribute (← c.getObjValAs? Nat "aid") (← c.getObjValAs? Nat "owner")
      (← c.getObjValAs? Nat "submittedAt") (← opOfJson (← c.getObjVal? "op")))
  | .error _ =>
  match j.getObjVal? "fold" with
  | .ok f =>
    let batch ← (← f.getObjVal? "batch").getArr?
    let entries ← batch.toList.mapM fun e => do
      pure ((← e.getObjValAs? Nat "id"), (← foldActionOfJson (← e.getObjVal? "do")))
    pure (.fold (← f.getObjValAs? Nat "folder") (← f.getObjValAs? Nat "gen") (← f.getObjValAs? Nat "plugin") entries)
  | .error _ =>
  match j.getObjVal? "retract" with
  | .ok r => pure (.retract (← r.getObjValAs? Nat "req"))
  | .error _ =>
  match j.getObjVal? "reap" with
  | .ok r => pure (.reap (← r.getObjValAs? Nat "reaper") (← r.getObjValAs? Nat "aid"))
  | .error _ =>
  match j.getObjVal? "pause" with
  | .ok r => pure (.pause (← r.getObjValAs? Nat "aid"))
  | .error _ =>
  match j.getObjVal? "resume" with
  | .ok r => pure (.resume (← r.getObjValAs? Nat "aid"))
  | .error _ =>
  match j.getObjVal? "convictCkpt" with
  | .ok r => pure (.convictCkpt (← r.getObjValAs? Nat "aid"))
  | .error _ => throw "unknown action"

/-! ## Cells -/

def params : Params := { D := 1000, tip := 2, Mc := 4, Mr := 1, process := 10, retract := 10, W := 5,
                         far := 1000000000, hD := by decide, hProcess := by decide, hRetract := by decide,
                         hFund := by decide }

def cellJson (p : Params) (env : Env) (now : Slot) (s : Sys) (a : Action) : Json × Sys :=
  match stepFn p env a now s with
  | some (f, s') =>
      (Json.mkObj [("now", toJson now), ("input", toJson s), ("action", toJson a),
        ("result", Json.mkObj [("flow", toJson f), ("state", toJson s')])], s')
  | none =>
      (Json.mkObj [("now", toJson now), ("input", toJson s), ("action", toJson a), ("result", Json.null)], s)

def runTrace (p : Params) (env : Env) : Sys → List (Slot × Action) → List Json
  | _, [] => []
  | s, (t, a) :: rest =>
      let (j, s') := cellJson p env t s a
      j :: runTrace p env s' rest

structure Seed where
  name : String
  env : EnvTable
  steps : List (Slot × Action)

/-- Alice = 1, Bob = 2, Hal = 3, Mallory = 4, Cora = 5, Sam = 6; AIDs 11, 12, 13; plugin 7. -/
def seeds : List Seed := [
  { name := "register",
    env := ⟨[11], [], [], []⟩,
    steps := [(0, .contribute 11 1 0 .register), (3, .fold 3 0 7 [(0, .process)]), (3, .fold 3 0 7 [(0, .process)]),
              (4, .contribute 11 4 4 .register), (5, .fold 3 1 7 [(1, .process)]), (25, .fold 6 1 7 [(1, .reject)])] },
  { name := "race",
    env := ⟨[11, 12], [], [], []⟩,
    steps := [(0, .contribute 11 1 0 .register), (0, .contribute 12 2 0 .register),
              (2, .fold 3 0 7 [(0, .process), (1, .process)]),
              (2, .fold 4 0 7 [(0, .process), (1, .process)]), (3, .fold 4 1 7 []), (3, .fold 4 1 8 [(0, .process)])] },
  { name := "retract-and-sweep",
    env := ⟨[11], [], [], []⟩,
    steps := [(0, .contribute 11 1 0 .register), (3, .retract 0), (12, .retract 0), (12, .retract 0),
              (12, .contribute 11 1 12 .register), (25, .fold 6 0 7 [(1, .reject)]), (33, .fold 6 0 7 [(1, .reject)])] },
  { name := "pause-reap-revive",
    env := ⟨[11], [(11, 0), (11, 1)], [], []⟩,
    steps := [(0, .contribute 11 1 0 .register), (1, .fold 3 0 7 [(0, .process)]), (5, .pause 11), (6, .reap 6 11),
              (10, .reap 6 11), (10, .retract 1), (10, .fold 3 1 7 [(1, .reject)]), (11, .fold 3 1 7 [(1, .process)]),
              (12, .contribute 11 1 12 .revive), (13, .fold 3 2 7 [(2, .process)])] },
  { name := "convict-and-reap",
    env := ⟨[12], [], [(12, 0)], []⟩,
    steps := [(0, .contribute 12 2 0 .register), (1, .fold 3 0 7 [(0, .process)]), (5, .convictCkpt 12),
              (5, .convictCkpt 12), (5, .reap 6 12), (6, .fold 3 1 7 [(1, .process)]),
              (7, .contribute 12 2 7 .register), (8, .fold 3 2 7 [(2, .process)]), (26, .fold 6 2 7 [(2, .reject)])] },
  { name := "owner-and-phases",
    env := ⟨[11], [(11, 0), (11, 1)], [], [11]⟩,
    steps := [(0, .contribute 11 1 0 .register), (5, .fold 6 0 7 [(0, .reject)]), (12, .fold 3 0 7 [(0, .process)]),
              (12, .contribute 11 4 100 .register), (12, .fold 6 0 7 [(1, .reject)]), (12, .contribute 11 4 0 .goConvicted),
              (12, .fold 3 1 7 [(0, .reject)]), (13, .contribute 11 1 13 .register), (14, .fold 3 2 7 [(2, .process)]),
              (15, .pause 11), (16, .reap 1 11), (16, .resume 11)] }
]

def traceJson (p : Params) (sd : Seed) : Json :=
  let s0 := Sys.init 7
  Json.mkObj [("name", toJson sd.name), ("plugin", toJson (7 : Nat)), ("env", toJson sd.env),
    ("initial", toJson s0), ("steps", Json.arr (runTrace p sd.env.toEnv s0 sd.steps).toArray)]

def enumL (l : List α) : List (Nat × α) := (List.range l.length).zip l

/-! ## The boundary grid, at slot 20 -/

/-- Genesis, and a system with a leaf of every status, a checkpoint of every
state, and a request of every op in every phase. AIDs: 11 active with a live
checkpoint; 12 active with a parked checkpoint since 12 (grace ends at 17);
13 active with a parked checkpoint since 16 (grace ends at 21); 14 active
with a tombstone; 15 active with a pending go-request; 16 dormant; 17
convicted. -/
def gridStates : List Sys :=
  [Sys.init 7,
   { gen := 3, plugin := 7,
     leaves := [(11, .active 0), (12, .active 1), (13, .active 2), (14, .active 3), (15, .active 4),
                (16, .dormant 5), (17, .convicted)],
     ckpts := [(11, ⟨0, 0, .live⟩), (12, ⟨1, 1, .parked 12⟩), (13, ⟨2, 1, .parked 16⟩), (14, ⟨3, 0, .tomb⟩)],
     requests := [(0, ⟨18, 1, 15, .register⟩), (1, ⟨18, 1, 5, .register⟩), (2, ⟨18, 1, 0, .register⟩),
                  (3, ⟨18, 4, 100, .register⟩), (4, ⟨11, 2, 15, .register⟩), (5, ⟨16, 1, 15, .revive⟩),
                  (6, ⟨16, 5, 15, .convict⟩), (7, ⟨15, 6, 1000000000, .goDormant 3⟩), (8, ⟨17, 1, 15, .revive⟩),
                  (9, ⟨11, 1, 15, .revive⟩)],
     nextReq := 10, nextToken := 5 }]

def gridBatches : List (List (ReqId × FoldAction)) :=
  [[]] ++ ([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map fun i => [(i, FoldAction.process)]) ++
  ([0, 1, 2, 3, 7].map fun i => [(i, FoldAction.reject)]) ++
  [[(0, .process), (0, .process)], [(0, .process), (2, .reject)], [(5, .process), (6, .process)]]

def gridActions : List Action :=
  ([Op.register, .revive, .convict, .goConvicted, .goDormant 1].map fun op => Action.contribute 18 1 20 op) ++
  ([0, 1, 2, 3, 7, 10].map fun i => Action.retract i) ++
  ([2, 3, 4].flatMap fun g => [7, 8].flatMap fun pl => gridBatches.map fun b => Action.fold 3 g pl b) ++
  ([11, 12, 13, 14, 15, 16].map fun a => Action.reap 6 a) ++
  ([11, 12, 14, 16].map fun a => Action.pause a) ++
  ([11, 12, 14, 16].map fun a => Action.resume a) ++
  ([11, 12, 14, 16].map fun a => Action.convictCkpt a)

def gridEnvs : List EnvTable :=
  [⟨[11, 12, 13, 14, 15, 16, 17, 18], [(11, 0), (12, 1), (13, 1), (16, 5)], [(11, 0), (12, 1), (16, 5)],
    [11, 12, 13, 14]⟩,
   ⟨[], [], [], []⟩]

def gridJson (p : Params) : Json :=
  let now : Slot := 20
  let cells : List Json :=
    (enumL gridStates).flatMap fun (si, s) =>
      (enumL gridActions).flatMap fun (ai, a) =>
        (enumL gridEnvs).map fun (ei, t) =>
          let (j, _) := cellJson p t.toEnv now s a
          Json.mkObj [("s", toJson si), ("a", toJson ai), ("e", toJson ei),
            ("result", (j.getObjVal? "result").toOption.getD Json.null)]
  Json.mkObj [("now", toJson now), ("plugin", toJson (7 : Nat)), ("states", toJson gridStates),
    ("actions", toJson gridActions), ("envs", toJson gridEnvs), ("cells", Json.arr cells.toArray)]

/-! ## Story cells -/

/-- Fold a list of story steps from a state; the cells and the states after
each step (the trunk prefix a fork departs from). -/
def foldSteps (p : Params) (env : Env) (steps : Array Json) (s0 : Sys) :
    Except String (List Json × Array Sys) := do
  let mut s := s0
  let mut cells : List Json := []
  let mut states : Array Sys := #[s0]
  for st in steps do
    let now ← st.getObjValAs? Nat "now"
    let a ← actionOfJson (← st.getObjVal? "action")
    let (j, s') := cellJson p env now s a
    s := s'
    cells := cells ++ [j]
    states := states.push s'
  pure (cells, states)

/-- A story is a tree: the trunk, then every fork from the trunk state after
`at` steps (its own env when it brings one — another world). Fork cells are
labelled `f<id>.<i>` by the readers. -/
def storyJson (sc : Json) : Except String Json := do
  let id ← sc.getObjValAs? Nat "id"
  let p ← paramsOfJson (← sc.getObjVal? "params")
  let plugin ← sc.getObjValAs? Nat "plugin"
  let env ← envOfJson ((sc.getObjVal? "env").toOption.getD (Json.mkObj []))
  let steps ← (← sc.getObjVal? "steps").getArr?
  let (cells, states) ← foldSteps p env.toEnv steps (Sys.init plugin)
  let forksJ : Array Json := match sc.getObjVal? "forks" with
    | .ok j => j.getArr?.toOption.getD #[]
    | .error _ => #[]
  let mut forks : List Json := []
  for fk in forksJ do
    let fid ← fk.getObjValAs? String "id"
    let atN ← fk.getObjValAs? Nat "at"
    let fenv ← match fk.getObjVal? "env" with
      | .ok e => envOfJson e
      | .error _ => pure env
    let fsteps ← (← fk.getObjVal? "steps").getArr?
    match states[atN]? with
    | none => throw s!"fork {fid}: departs after {atN} steps, the trunk has {states.size - 1}"
    | some s0 =>
      let (fcells, _) ← foldSteps p fenv.toEnv fsteps s0
      forks := forks ++ [Json.mkObj [("id", toJson fid), ("at", toJson atN), ("env", toJson fenv),
        ("steps", Json.arr fcells.toArray)]]
  pure (Json.mkObj [("id", toJson id), ("params", toJson p), ("env", toJson env),
    ("steps", Json.arr cells.toArray), ("forks", Json.arr forks.toArray)])

def readScenarios : IO (List Json) := do
  let dir : System.FilePath := "../simulator/registry-simulator-scenarios"
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
    ("schema", "cardano-keri.registry.trace"), ("version", (2 : Nat)), ("params", toJson params),
    ("traces", Json.arr (seeds.map (traceJson params)).toArray),
    ("grid", gridJson params),
    ("stories", Json.arr stories.toArray)]).compress

end CardanoKeri.Registry.TraceDriver
