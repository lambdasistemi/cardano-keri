import Lean
import CardanoKeri.Registry

/-!
# The registry — trace interchange v1 producer

Emits the `cardano-keri.registry.trace` version-1 corpus embedded by
`simulator/registry-simulator.html`: `Sys`, `Action`, `Flow` and `Params` are
serialized by hand-written `ToJson` instances over the authoritative
`stepFn` of `CardanoKeri.Registry` — never `Repr` parsing, never JavaScript.
Every cell carries its explicit input state, the slot, the action, and the
result (`null` when `stepFn` refuses; otherwise the `Flow` and the post-state),
so a verifier can check continuity and conformance without trusting anyone's
memory.

Three families of cells:

* six **seeded traces**, the stories a player must see land and the refusals
  they must see named;
* a **boundary grid**: two systems (genesis, and one with a request in every
  phase, a live checkpoint, a tombstone) × every action shape at every
  guard's −1 / = / +1 × two evidence oracles (everything, nothing);
* the **story cells**: the fifteen scenario files of the simulator, replayed
  through `stepFn` from their own params, plugin and evidence table — the
  Lean's own verdict on every story step, which the JavaScript core must
  reproduce.

Reproducible from a clean checkout with

```sh
cd lean && nix shell nixpkgs#lean4 -c lake build CardanoKeri.Registry
cd lean && nix shell nixpkgs#lean4 -c lake env lean RegistryTraceDriver.lean
```

(`simulator/registry-simulator-trace-gate.mjs` runs exactly that, compares
the fresh output against the embedded fixture by sha256, and replays it
through the page's production JavaScript.)
-/

open Lean (ToJson toJson Json FromJson fromJson?)

namespace CardanoKeri.Registry.TraceDriver

/-! ## Wire serialization -/

instance : ToJson Params where
  toJson p := Json.mkObj [("D", toJson p.D), ("tip", toJson p.tip),
                          ("process", toJson p.process), ("retract", toJson p.retract)]

private def requestJson (id : ReqId) (r : Request) : Json :=
  Json.mkObj [("id", toJson id), ("aid", toJson r.aid), ("owner", toJson r.owner),
              ("submittedAt", toJson r.submittedAt)]

instance : ToJson Sys where
  toJson s := Json.mkObj [("gen", toJson s.gen), ("plugin", toJson s.plugin),
    ("root", toJson s.root), ("live", toJson s.live), ("tomb", toJson s.tomb),
    ("requests", Json.arr (s.requests.map fun (id, r) => requestJson id r).toArray),
    ("nextReq", toJson s.nextReq)]

private def foldActionJson : FoldAction → Json
  | .process => Json.str "process"
  | .reject => Json.str "reject"

instance : ToJson Action where
  toJson
    | .contribute aid owner t => Json.mkObj [("contribute", Json.mkObj
        [("aid", toJson aid), ("owner", toJson owner), ("submittedAt", toJson t)])]
    | .fold folder g pl batch => Json.mkObj [("fold", Json.mkObj
        [("folder", toJson folder), ("gen", toJson g), ("plugin", toJson pl),
         ("batch", Json.arr (batch.map fun (id, fa) =>
            Json.mkObj [("id", toJson id), ("do", foldActionJson fa)]).toArray)])]
    | .retract id => Json.mkObj [("retract", Json.mkObj [("req", toJson id)])]
    | .close aid => Json.mkObj [("close", Json.mkObj [("aid", toJson aid)])]
    | .convict aid => Json.mkObj [("convict", Json.mkObj [("aid", toJson aid)])]

instance : ToJson Flow where
  toJson f := Json.mkObj [("deposited", toJson f.deposited),
    ("locked", Json.arr (f.locked.map fun (aid, v) => Json.mkObj [("aid", toJson aid), ("value", toJson v)]).toArray),
    ("refunds", Json.arr (f.refunds.map fun (a, v) => Json.mkObj [("addr", toJson a), ("value", toJson v)]).toArray),
    ("tips", match f.tips with
      | some (a, v) => Json.mkObj [("addr", toJson a), ("value", toJson v)]
      | none => Json.null)]

/-- An evidence table: the AIDs for which each predicate holds. -/
structure EnvTable where
  inception : List AID
  quorum : List AID
  duplicity : List AID

def EnvTable.toEnv (t : EnvTable) : Env :=
  { inception := fun a => t.inception.contains a,
    quorum := fun a => t.quorum.contains a,
    duplicity := fun a => t.duplicity.contains a }

instance : ToJson EnvTable where
  toJson t := Json.mkObj [("inception", toJson t.inception), ("quorum", toJson t.quorum),
                          ("duplicity", toJson t.duplicity)]

/-! ## Parsing the scenario files -/

def natList (j : Json) : Except String (List Nat) := fromJson? j

def envOfJson (j : Json) : Except String EnvTable := do
  let get (k : String) : Except String (List Nat) := match j.getObjVal? k with
    | .ok v => natList v
    | .error _ => pure []
  pure ⟨← get "inception", ← get "quorum", ← get "duplicity"⟩

def paramsOfJson (j : Json) : Except String Params := do
  let D ← j.getObjValAs? Nat "D"
  let tip ← j.getObjValAs? Nat "tip"
  let process ← j.getObjValAs? Nat "process"
  let retract ← j.getObjValAs? Nat "retract"
  if hD : 0 < D then
    if hP : 0 < process then
      if hR : 0 < retract then
        pure { D, tip, process, retract, hD, hProcess := hP, hRetract := hR }
      else throw "retract must be positive"
    else throw "process must be positive"
  else throw "D must be positive"

def foldActionOfJson (j : Json) : Except String FoldAction := do
  match ← j.getStr? with
  | "process" => pure .process
  | "reject" => pure .reject
  | s => throw s!"unknown fold action {s}"

def actionOfJson (j : Json) : Except String Action := do
  match j.getObjVal? "contribute" with
  | .ok c => pure (.contribute (← c.getObjValAs? Nat "aid") (← c.getObjValAs? Nat "owner") (← c.getObjValAs? Nat "submittedAt"))
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
  match j.getObjVal? "close" with
  | .ok c => pure (.close (← c.getObjValAs? Nat "aid"))
  | .error _ =>
  match j.getObjVal? "convict" with
  | .ok c => pure (.convict (← c.getObjValAs? Nat "aid"))
  | .error _ => throw "unknown action"

/-! ## Cells -/

/-- The deployment used by the seeds and the grid. -/
def params : Params := { D := 1000, tip := 2, process := 10, retract := 10,
                         hD := by decide, hProcess := by decide, hRetract := by decide }

/-- One cell: the slot, the input state, the action and the result
(`null` when `stepFn` refuses). -/
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
    env := ⟨[11], [], []⟩,
    steps := [(0, .contribute 11 1 0), (3, .fold 3 0 7 [(0, .process)]), (3, .fold 3 0 7 [(0, .process)])] },
  { name := "race",
    env := ⟨[11, 12], [], []⟩,
    steps := [(0, .contribute 11 1 0), (0, .contribute 12 2 0),
              (2, .fold 3 0 7 [(0, .process), (1, .process)]),
              (2, .fold 4 0 7 [(0, .process), (1, .process)]), (3, .fold 4 1 7 []), (3, .fold 4 1 8 [(0, .process)])] },
  { name := "retract-and-sweep",
    env := ⟨[11], [], []⟩,
    steps := [(0, .contribute 11 1 0), (3, .retract 0), (12, .retract 0), (12, .retract 0),
              (12, .contribute 11 1 12), (25, .fold 6 0 7 [(1, .reject)]), (33, .fold 6 0 7 [(1, .reject)])] },
  { name := "close-and-return",
    env := ⟨[11], [11], []⟩,
    steps := [(0, .contribute 11 1 0), (1, .fold 3 0 7 [(0, .process)]), (4, .convict 11), (5, .close 11),
              (5, .close 11), (6, .contribute 11 1 6), (7, .fold 3 2 7 [(1, .process)])] },
  { name := "convict",
    env := ⟨[12], [12], [12]⟩,
    steps := [(0, .contribute 12 2 0), (1, .fold 3 0 7 [(0, .process)]), (5, .convict 12), (5, .convict 12),
              (6, .contribute 12 2 6), (7, .fold 3 1 7 [(1, .process)]), (8, .close 12),
              (26, .fold 6 1 7 [(1, .reject)])] },
  { name := "phases",
    env := ⟨[11], [], []⟩,
    steps := [(0, .contribute 11 1 0), (5, .fold 6 0 7 [(0, .reject)]), (12, .fold 3 0 7 [(0, .process)]),
              (12, .contribute 11 4 100), (12, .fold 6 0 7 [(1, .reject)]), (12, .fold 6 1 7 [(0, .reject)]),
              (20, .fold 6 1 7 [(0, .reject)])] }
]

def traceJson (p : Params) (sd : Seed) : Json :=
  let s0 := Sys.init 7
  Json.mkObj [("name", toJson sd.name), ("plugin", toJson (7 : Nat)), ("env", toJson sd.env),
    ("initial", toJson s0), ("steps", Json.arr (runTrace p sd.env.toEnv s0 sd.steps).toArray)]

def enumL (l : List α) : List (Nat × α) := (List.range l.length).zip l

/-! ## The boundary grid, at slot 20 -/

/-- Genesis, and a system with a request in every phase (submitted at 15,
5, 0, and 100 — the future), one for a registered AID and one for a
convicted AID, a live checkpoint (12) and a tombstone (13). -/
def gridStates : List Sys :=
  [Sys.init 7,
   { gen := 1, plugin := 7, root := [12, 13], live := [12], tomb := [13],
     requests := [(0, ⟨11, 1, 15⟩), (1, ⟨11, 1, 5⟩), (2, ⟨11, 1, 0⟩), (3, ⟨11, 4, 100⟩),
                  (4, ⟨12, 2, 15⟩), (5, ⟨13, 2, 15⟩)],
     nextReq := 6 }]

def gridBatches : List (List (ReqId × FoldAction)) :=
  [[]] ++ ([0, 1, 2, 3, 4, 5, 6].map fun i => [(i, FoldAction.process)]) ++
  ([0, 1, 2, 3].map fun i => [(i, FoldAction.reject)]) ++
  [[(0, .process), (0, .process)], [(0, .process), (2, .reject)], [(4, .process), (0, .process)]]

/-- Every action shape at every guard's −1 / = / +1: generations 0, 1, 2
against a registry at 1; plugins 7 and 8; every batch; every request
identifier for retract including an unknown one; close and convict on a
pending, a live and a convicted AID. -/
def gridActions : List Action :=
  [.contribute 11 1 20] ++
  ([0, 1, 2, 3, 4, 5, 6].map fun i => Action.retract i) ++
  ([0, 1, 2].flatMap fun g => [7, 8].flatMap fun pl => gridBatches.map fun b => Action.fold 3 g pl b) ++
  ([11, 12, 13].map fun a => Action.close a) ++
  ([11, 12, 13].map fun a => Action.convict a)

def gridEnvs : List EnvTable :=
  [⟨[11, 12, 13], [11, 12, 13], [11, 12, 13]⟩, ⟨[], [], []⟩]

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

/-! ## Story cells: the Lean's verdict on every step of the scenario files -/

def storyJson (sc : Json) : Except String Json := do
  let id ← sc.getObjValAs? Nat "id"
  let p ← paramsOfJson (← sc.getObjVal? "params")
  let plugin ← sc.getObjValAs? Nat "plugin"
  let env ← envOfJson ((sc.getObjVal? "env").toOption.getD (Json.mkObj []))
  let steps ← (← sc.getObjVal? "steps").getArr?
  let mut s := Sys.init plugin
  let mut cells : List Json := []
  for st in steps do
    let now ← st.getObjValAs? Nat "now"
    let a ← actionOfJson (← st.getObjVal? "action")
    let (j, s') := cellJson p env.toEnv now s a
    s := s'
    cells := cells ++ [j]
  pure (Json.mkObj [("id", toJson id), ("params", toJson p), ("env", toJson env),
    ("steps", Json.arr cells.toArray)])

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
    ("schema", "cardano-keri.registry.trace"), ("version", (1 : Nat)), ("params", toJson params),
    ("traces", Json.arr (seeds.map (traceJson params)).toArray),
    ("grid", gridJson params),
    ("stories", Json.arr stories.toArray)]).compress

end CardanoKeri.Registry.TraceDriver
