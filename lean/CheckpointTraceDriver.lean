import Lean
import CardanoKeri.Checkpoint

/-!
# The M1 checkpoint — trace interchange v1 producer

Emits the frozen `cardano-keri.checkpoint.trace` version-1 seed corpus
embedded by `simulator/checkpoint-simulator.html` as
`CHECKPOINT_LEAN_TRACES_V1`: `State`, `Action`, `Flow` and `Params` are
serialized by hand-written `ToJson` instances over the authoritative
`stepFn` of `CardanoKeri.Checkpoint` — never `Repr` parsing, never
JavaScript. Every step carries its explicit input state (`before`), the
slot, the action, the `Flow`, and the post-state (`after`) computed by
`stepFn`, so a verifier can check continuity and conformance without
trusting anyone's memory.

The evidence environment `Env` is a set of predicates; it is seeded from
explicit decision tables (a row not listed is false) that are serialized
alongside the steps, so the JavaScript side rebuilds exactly the predicates
this driver stepped with.

The driver is the durable artifact; its JSON output is disposable and
reproducible from a clean checkout with:

```sh
cd lean && nix shell nixpkgs#lean4 -c lake build CardanoKeri.Checkpoint
cd lean && nix shell nixpkgs#lean4 -c lake env lean CheckpointTraceDriver.lean
```

(`simulator/checkpoint-simulator-trace-gate.mjs` runs exactly that,
compares the fresh output against the embedded fixture by sha256, and
replays it through the page's production JavaScript.)

The six seeded traces are the stories a player must see land: the happy
path, freeze then unfreeze, pause then resurrect, poison then rotate,
convict, close. If any seeded step is refused, the driver throws instead of
emitting a usable-looking corpus: the seed contains applied steps only.
-/

open Lean (ToJson toJson Json)

namespace CardanoKeri.Checkpoint.TraceDriver

/-! ## Wire serialization (hand-written ToJson, the v1 envelope shapes) -/

instance : ToJson Params where
  toJson p := Json.mkObj [("D", toJson p.D), ("B", toJson p.B),
                          ("P", toJson p.P), ("W", toJson p.W)]

private def stateJson : State → Json
  | .absent => Json.str "absent"
  | .gone => Json.str "gone"
  | .present l => Json.mkObj [("present", Json.mkObj
      [("sn", toJson l.sn), ("epoch", toJson l.epoch),
       ("poisoned", toJson l.poisoned), ("bornAt", toJson l.bornAt),
       ("refundTo", toJson l.refundTo), ("dreg", toJson l.dreg),
       ("b", toJson l.b), ("pool", toJson l.pool)])]
  | .convicted e sn c => Json.mkObj [("convicted", Json.mkObj
      [("epoch", toJson e), ("sn", toJson sn), ("convictedAt", toJson c)])]

instance : ToJson State := ⟨stateJson⟩

private def opJson : BondOp → Json
  | .keep => Json.str "keep"
  | .withdraw => Json.str "withdraw"
  | .deposit => Json.str "deposit"

private def optJson : Option Json → Json
  | some j => j
  | none => Json.null

private def actionJson : Action → Json
  | .register r p0 => Json.mkObj [("register", Json.mkObj
      [("refund", toJson r), ("pool0", toJson p0)])]
  | .rotate sn' op payee r' => Json.mkObj [("rotate", Json.mkObj
      [("sn", toJson sn'), ("op", opJson op), ("payee", toJson payee),
       ("refund", optJson (r'.map toJson))])]
  | .poison => Json.mkObj [("poison", Json.mkObj [])]
  | .freeze sn' payee => Json.mkObj [("freeze", Json.mkObj
      [("sn", toJson sn'), ("payee", toJson payee)])]
  | .topUp x => Json.mkObj [("topUp", Json.mkObj [("x", toJson x)])]
  | .convict payee => Json.mkObj [("convict", Json.mkObj [("payee", toJson payee)])]
  | .close => Json.mkObj [("close", Json.mkObj [])]

instance : ToJson Action := ⟨actionJson⟩

private def paymentJson (q : Payment) : Json :=
  Json.mkObj [("addr", toJson q.addr), ("dreg", toJson q.dreg),
              ("b", toJson q.b), ("pool", toJson q.pool)]

private def flowJson (f : Flow) : Json :=
  Json.mkObj [("dregIn", toJson f.dregIn), ("bIn", toJson f.bIn),
              ("poolIn", toJson f.poolIn),
              ("refund", optJson (f.refund.map paymentJson)),
              ("hunter", optJson (f.hunter.map paymentJson)),
              ("convictor", optJson (f.convictor.map paymentJson))]

instance : ToJson Flow := ⟨flowJson⟩

/-! ## Evidence tables: the seedable `Env`

The predicates are seeded from decision tables and serialized from the same
tables, so what the verifier rebuilds is exactly what `stepFn` consumed. -/

abbrev RotTable := List ((Epoch × Seq × Seq) × Bool)
abbrev RefTable := List ((Epoch × Addr) × Bool)
abbrev QuoTable := List (Epoch × Bool)
abbrev DupTable := List ((Epoch × Seq) × Bool)

def tableEnv (rot : RotTable) (ref : RefTable) (quo : QuoTable) (dup : DupTable) : Env :=
  { rotationTo := fun e s1 s2 => (rot.lookup (e, s1, s2)).getD false
    refundAuthorized := fun e a => (ref.lookup (e, a)).getD false
    quorum := fun e => (quo.lookup e).getD false
    duplicityAt := fun e s => (dup.lookup (e, s)).getD false }

def tableJson (rot : RotTable) (ref : RefTable) (quo : QuoTable) (dup : DupTable) : Json :=
  Json.mkObj
    [ ("rotationTo", Json.arr ((rot.map fun r =>
        Json.arr #[toJson r.1.1, toJson r.1.2.1, toJson r.1.2.2, toJson r.2])).toArray)
    , ("refundAuthorized", Json.arr ((ref.map fun r =>
        Json.arr #[toJson r.1.1, toJson r.1.2, toJson r.2])).toArray)
    , ("quorum", Json.arr ((quo.map fun r =>
        Json.arr #[toJson r.1, toJson r.2])).toArray)
    , ("duplicityAt", Json.arr ((dup.map fun r =>
        Json.arr #[toJson r.1.1, toJson r.1.2, toJson r.2])).toArray) ]

/-! ## The seeded traces -/

def theParams : Params :=
  { D := 1000, B := 5, P := 2, W := 10, hD := by decide, hB := by decide }

def stepEnvelope (now : Slot) (a : Action) (before : State) (f : Flow) (after : State) : Json :=
  Json.mkObj [("now", toJson now), ("action", toJson a), ("before", toJson before),
              ("flow", toJson f), ("after", toJson after)]

/-- Fold the seeds through the authoritative `stepFn`; `none` as soon as any
seeded step is refused, so a broken seed can never emit a partial corpus. -/
partial def runSeeds (p : Params) (env : Env) (s : State) :
    List (Slot × Action) → IO (List Json)
  | [] => pure []
  | (now, a) :: rest => do
      match stepFn p env a now s with
      | some (f, s') =>
          let head := stepEnvelope now a s f s'
          let tail ← runSeeds p env s' rest
          pure (head :: tail)
      | none =>
          throw <| IO.userError
            s!"SEED-STEP-REFUSED at slot {now}: the seeded action was refused; no corpus emitted"

def traceEnvelope (p : Params) (rot : RotTable) (ref : RefTable) (quo : QuoTable)
    (dup : DupTable) (seeds : List (Slot × Action)) : IO Json := do
  let env := tableEnv rot ref quo dup
  let steps ← runSeeds p env .absent seeds
  pure <| Json.mkObj [("params", toJson p), ("env", tableJson rot ref quo dup),
                      ("initial", toJson State.absent),
                      ("steps", Json.arr steps.toArray)]

/-- Happy path: register, a paid rotation landed by the hunter, a top-up. -/
def happyPath : IO Json :=
  traceEnvelope theParams [((0, 0, 1), true)] [((1, 1), true)] [(0, true)] []
    [ (0, .register 1 5)
    , (5, .rotate 1 .keep 2 (some 1))
    , (7, .topUp 4) ]

/-- Freeze then unfreeze: the pool cannot pay, a hunter takes `B`, the owner
lands the same rotation as a deposit and a friend tops the pool up. -/
def freezeUnfreeze : IO Json :=
  traceEnvelope theParams [((0, 0, 1), true)] [((1, 1), true)] [(0, true)] []
    [ (0, .register 1 1)
    , (5, .freeze 1 2)
    , (10, .rotate 1 .deposit 2 (some 1))
    , (12, .topUp 3) ]

/-- Pause then resurrect: a withdrawing rotation pays everything to the
refund address; a depositing rotation brings both bonds back. -/
def pauseResurrect : IO Json :=
  traceEnvelope theParams [((0, 0, 1), true), ((1, 1, 2), true)]
    [((1, 1), true), ((2, 1), true)] [(0, true)] []
    [ (0, .register 1 7)
    , (5, .rotate 1 .withdraw 2 (some 1))
    , (10, .rotate 2 .deposit 2 none) ]

/-- Poison then rotate: the current quorum poisons the epoch — consumers
stop trusting it, close is disabled — and the rotation clears the poison
because it was local to the retired keys. (The seed contains applied steps
only: refusals belong to the scenarios, not to this corpus.) -/
def poisonThenRotate : IO Json :=
  traceEnvelope theParams [((0, 0, 1), true)] [((1, 1), true)] [(0, true)] []
    [ (0, .register 1 3)
    , (5, .poison)
    , (10, .rotate 1 .keep 2 none) ]

/-- Convict: a verified duplicity proof ends the machine; the conviction
bond goes to the convictor, the freeze bond and the pool to the refund
address (the modelled assumption of D-034). -/
def convict : IO Json :=
  traceEnvelope theParams [] [] [(0, true)] [((0, 0), true)]
    [ (0, .register 1 6)
    , (5, .convict 3) ]

/-- Close: the current quorum, unpoisoned; everything to the refund address,
the closer chooses when, never where. -/
def close : IO Json :=
  traceEnvelope theParams [] [] [(0, true)] []
    [ (0, .register 1 3)
    , (5, .close) ]

#eval do
  let happy ← happyPath
  let freeze ← freezeUnfreeze
  let pause ← pauseResurrect
  let poison ← poisonThenRotate
  let convictJ ← convict
  let closeJ ← close
  let doc := Json.mkObj
    [ ("schema", Json.str "cardano-keri.checkpoint.trace")
    , ("version", toJson (1 : Nat))
    , ("traces", Json.mkObj
        [ ("happy-path", happy)
        , ("freeze-unfreeze", freeze)
        , ("pause-resurrect", pause)
        , ("poison-then-rotate", poison)
        , ("convict", convictJ)
        , ("close", closeJ) ]) ]
  IO.println doc.compress

end CardanoKeri.Checkpoint.TraceDriver
