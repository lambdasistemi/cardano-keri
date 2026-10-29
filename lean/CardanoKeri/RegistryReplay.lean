import CardanoKeri.Registry

/-! Finite certificates for actual Registry histories. Every certificate action
is executed in the context supplied by its owner; it cannot supply a fresh
environment part way through the history. Refusal stops the certificate. -/
namespace CardanoKeri.Registry

def replay (p : Params) (env : Env) (start : Sys) : List Action → Except String Sys
  | [] => .ok start
  | action :: rest => do
    let (_, after) ← stepFn p env action start
    replay p env after rest

/-- Given two actual histories under the same parameters and environment,
when the second starts at the first's final state, then their concatenation
is an actual history under that same context. -/
theorem History.trans {p : Params} {env : Env} {a b c : Sys}
    (first : History p env a b) (second : History p env b c) : History p env a c := by
  induction second with
  | refl => exact first
  | step history executed ih => exact History.step ih executed

/-- Given an actual history and a reachable starting state under its fixed
configuration, when that history finishes, then its final state is reachable
under precisely the same parameters, environment and initial configuration. -/
theorem History.reachable {p : Params} {env : Env} {cfg : Singular.Config} {a b : Sys}
    (history : History p env a b) (initial : Reach p env cfg a) : Reach p env cfg b := by
  induction history with
  | refl => exact initial
  | step history executed ih => exact Reach.next ih executed

/-- Given a starting snapshot and a finite action certificate, when replay
succeeds in one fixed context, then the actual Registry History relates that
snapshot to the returned state. This is not a claim about refused prefixes. -/
theorem replay_history (p : Params) (env : Env) (actions : List Action)
    {start after : Sys} (accepted : replay p env start actions = .ok after) :
    History p env start after := by
  induction actions generalizing start with
  | nil => simp only [replay, Except.ok.injEq] at accepted; subst after; exact .refl start
  | cons action rest ih =>
    cases executed : stepFn p env action start with
    | error why => simp [replay, executed, bind, Except.bind] at accepted
    | ok result =>
      obtain ⟨flow, next⟩ := result
      simp only [replay, executed, bind, Except.bind] at accepted
      exact (History.step (History.refl start) executed).trans (ih accepted)

def completesB {p : Params} {env : Env} {cfg : Singular.Config}
    (receipt : FoldReceipt p env cfg) (ref : Singular.OutRef) (aid token : Nat) : Bool :=
  match pendingAt receipt.before ref with
  | none => false
  | some entry => entry.payload.aid == aid && entry.payload.token == token &&
      Singular.inputsContainReference receipt.transaction.transaction.inputs ref

/-- Given an actual context-indexed fold receipt and an exact request, AID and
alias, when the executable completion test is true, then and only then the
model's Completes proposition holds for that same receipt and tuple. -/
theorem completesB_iff {p : Params} {env : Env} {cfg : Singular.Config}
    (receipt : FoldReceipt p env cfg) (ref : Singular.OutRef) (aid token : Nat) :
    completesB receipt ref aid token = true ↔ Completes receipt ref aid token := by
  cases found : pendingAt receipt.before ref <;> simp [completesB, Completes, found, and_assoc]

end CardanoKeri.Registry
