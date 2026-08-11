import PlutusCore.UPLC

/-!
Collector-closure control.  The semantic collector does not name leading-dot
syntax (or any other Lean spelling); Lean's own `.ilean` reference map records
the resolved constructor occurrence.  The in-process mutant renames `.Halt`
to absent `.Stop` and must fail elaboration under the pinned module graph.
-/

def collectorClosureReference
    (state : PlutusCore.UPLC.CekMachine.State) : Bool :=
  match state with
  | .Halt _ => true
  | _ => false
