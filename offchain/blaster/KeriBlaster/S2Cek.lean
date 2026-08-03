import PlutusCore.UPLC

/-!
# Instrumented CEK execution for the S2 reachability evidence

The pinned `cekExecuteProgram` returns only a final `State`, which cannot
distinguish "this program never used that builtin" from "the evaluator had no
case for it". Reachability is exactly that distinction, so this module runs
the pinned `step` function itself and records what the machine actually did.

Reached means the machine evaluated a `Builtin` term, not that the builtin
occurs somewhere in the decoded program. Syntactic occurrence is recorded
separately and is never reported as reachability.

Nothing here reimplements evaluation: every transition is the pinned
`step`, so an outcome observed through this runner is an outcome of the
pinned evaluator.
-/

namespace KeriBlaster.S2.Cek

open PlutusCore.Default (BuiltinSemanticsVariant)
open PlutusCore.UPLC.Term (BuiltinFun Program Term Version)
open PlutusCore.UPLC.CekValue (CekValue Environment)
open PlutusCore.UPLC.CekMachine
  (State applyParams initialState step versionToSemanticsVariant)

/-- What the machine did, as opposed to what the program contains. -/
structure Trace where
  /-- the state the machine stopped in -/
  final : State
  /-- builtins whose `Builtin` term the machine actually evaluated -/
  reached : List BuiltinFun
  /-- the most recent builtin the machine had in hand, for attributing an
  `Error` to a named builtin rather than reporting a bare failure -/
  lastBuiltin : Option BuiltinFun
  /-- the builtin whose own *dispatch* produced the error, when the erroring
  transition was a builtin application.

  This is a different fact from `lastBuiltin` and the distinction is the
  whole point: `lastBuiltin` answers "what had the machine touched most
  recently", which an explicit `Error` term inherits from unrelated
  neighbouring work, whereas this answers "which builtin did the pinned
  evaluator refuse to produce a result for". Only the second can identify an
  unsupported builtin.
  -/
  dispatchFailure : Option BuiltinFun
  /-- steps consumed; reported so a bounded run carries its measured cost -/
  steps : Nat
  /-- whether the step budget ran out before the machine settled -/
  exhausted : Bool

/-- A bounded runner must be compilable as a `partial` definition, which
requires its result type to be inhabited. The witness is the honest
"nothing observed" trace: an errored machine that took no steps. -/
instance : Inhabited Trace where
  default :=
    { final := .Error, reached := [], lastBuiltin := none
    , dispatchFailure := none, steps := 0, exhausted := false }

/-- Record a first-occurrence-preserving builtin. -/
def note (seen : List BuiltinFun) (found : BuiltinFun) : List BuiltinFun :=
  if seen.contains found then seen else seen ++ [found]

/-- The builtin a state is evaluating or holding, if any.

`Eval … (Builtin b)` is the reachability event: the machine is evaluating
that builtin term. `Return … (VBuiltin b …)` is the machine holding a
partially applied builtin, which is what an `Error` should be attributed to.
-/
def stateBuiltin : State → Option BuiltinFun
  | .Eval _ _ (.Builtin found) => some found
  | .Return _ (.VBuiltin found _ _) => some found
  | _ => none

/-- Whether a state is evaluating a builtin term, as opposed to merely
holding one. Only this counts as reached. -/
def evaluatesBuiltin : State → Option BuiltinFun
  | .Eval _ _ (.Builtin found) => some found
  | _ => none

/-- The builtin this state is about to hand to the pinned evaluator, if any.

The pinned `step` reaches `evalBuiltin` from three shapes. In two of them the
saturated `VBuiltin` is the value being returned, so looking at the value is
enough. In the third — the ordinary `f x` application, and by far the most
common — the `VBuiltin` sits in the `RightApplicationOfValue` frame while the
value being returned is the final *argument*.

Inspecting only the returned value therefore misses that dispatch entirely.
An `Error` raised by it would then be attributed to whichever builtin last
helped compute the argument: for
`blake2b_256(concat(tag, concat(0x45, aid)))` that is `AppendByteString`, a
builtin the pinned evaluator fully supports. Naming a supported builtin as
the site of an unsupported-builtin failure is worse than naming nothing,
which is why this looks into the frame.
-/
def dispatchingBuiltin : State → Option BuiltinFun
  | .Return (.RightApplicationOfValue (.VBuiltin found _ _) :: _) _ => some found
  | .Return (.LeftApplicationToValue _ :: _) (.VBuiltin found _ _) => some found
  | .Return (.ForceFrame :: _) (.VBuiltin found _ _) => some found
  | _ => none

/-- Run the pinned machine for at most `budget` steps, recording what it did.

Terminates on `Halt`, on `Error`, or when the step budget is exhausted. The
exhausted case is reported as such and is never conflated with an evaluation
error: that distinction is what makes a low-fuel control meaningful.
-/
partial def runFrom (variant : BuiltinSemanticsVariant) (state : State)
    (fuel : Nat) (seen : List BuiltinFun) (last : Option BuiltinFun)
    (dispatchFailed : Option BuiltinFun) (steps : Nat) : Trace :=
  let seen := match evaluatesBuiltin state with
    | some found => note seen found
    | none => seen
  let last := match stateBuiltin state with
    | some found => some found
    | none => last
  match state with
  | .Halt _ =>
      { final := state, reached := seen, lastBuiltin := last
      , dispatchFailure := dispatchFailed, steps := steps, exhausted := false }
  | .Error =>
      { final := state, reached := seen, lastBuiltin := last
      , dispatchFailure := dispatchFailed, steps := steps, exhausted := false }
  | _ =>
      match fuel with
      | 0 =>
          { final := state, reached := seen, lastBuiltin := last
          , dispatchFailure := dispatchFailed, steps := steps
          , exhausted := true }
      | Nat.succ remaining =>
          -- Attribution is decided at the transition, from the state the
          -- machine was in *before* it errored, because the `Error` state
          -- itself carries no stack and therefore no evidence of what was
          -- being dispatched.
          let next := step variant state
          let dispatchFailed := match next, dispatchingBuiltin state with
            | .Error, some found => some found
            | _, _ => dispatchFailed
          runFrom variant next remaining seen last dispatchFailed (steps + 1)

/-- Run the pinned machine for at most `budget` steps from a start state. -/
def runTraced (variant : BuiltinSemanticsVariant) (budget : Nat)
    (start : State) : Trace :=
  runFrom variant start budget [] none none 0

/-- The semantics variant a program's own version selects. -/
def variantOf : Program → BuiltinSemanticsVariant
  | .Program version _ => versionToSemanticsVariant version

/-- Apply arguments to a program body and run the pinned machine. -/
def runProgram (program : Program) (arguments : List Term) (budget : Nat) :
    Trace :=
  match program with
  | .Program _ body =>
      runTraced (variantOf program) budget
        (initialState (applyParams body arguments))

/-- A settled machine that produced a value. -/
def succeeded (trace : Trace) : Bool :=
  match trace.final with
  | .Halt _ => true
  | _ => false

/-- A settled machine that errored, as distinct from one that ran out of
steps. -/
def errored (trace : Trace) : Bool :=
  match trace.final with
  | .Error => !trace.exhausted
  | _ => false

/-- How an error was attributed, so the two distinct facts are never read as
one.

`builtin-dispatch` means the pinned evaluator returned no result for that
builtin on the exact arguments the machine supplied — the only shape that can
identify an unsupported builtin. `term-error` means the machine reached an
explicit `Error` term, which is how a validator's own rejection compiles, and
the accompanying name is only the last builtin in hand, not a culprit.
-/
def errorKind (trace : Trace) : String :=
  match trace.final, trace.exhausted with
  | .Error, false =>
      match trace.dispatchFailure with
      | some _ => "builtin-dispatch"
      | none => "term-error"
  | _, _ => "none"

/-- A short, stable description of how the machine stopped. -/
def outcome (trace : Trace) : String :=
  if trace.exhausted then "BUDGET-EXHAUSTED"
  else match trace.final with
    | .Halt _ => "HALT"
    | .Error => "ERROR"
    | _ => "UNSETTLED"

end KeriBlaster.S2.Cek
