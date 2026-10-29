import Freshness.Concepts

namespace Freshness.Examples
open Freshness CardanoKeri

/-- Illustrative units only; no price or fee calibration. -/
def params : Checkpoint.Params := ⟨3, 2, 10, 5, by decide, by decide⟩
/-- Hypothetical evidence oracle admitting consecutive, valid next events.
This does not establish that any real participant holds their signatures. -/
def environment : Checkpoint.Env :=
  { rotationTo := fun _ old next => decide (next = old + 1)
    intentAuthorized := fun _ _ _ => true
    quorum := fun _ => true
    convictionContext := fun _ _ => none
    convictionRival := fun _ _ => none }

def control : Control :=
  { roleOwner := fun
      | .sponsor => 0
      | .controller => 3
      | .monitor => 1
      | .submitter => 1
      | .consumer => 4
    addressOwner := fun addr => if addr = 101 then 1 else if addr = 102 then 2 else 0 }

def start : Checkpoint.State := .present ⟨0, 0, false, false, 0, 100, 20⟩
def first : Checkpoint.State := .present ⟨1, 1, false, false, 0, 100, 10⟩
def second : Checkpoint.State := .present ⟨2, 2, false, false, 0, 100, 0⟩
def third : Checkpoint.State := .present ⟨3, 3, false, false, 0, 100, 0⟩
def reward : Checkpoint.Flow := { hunter := some { addr := 101, pool := 10 } }
def rotate1 : Checkpoint.Action := .rotate 1 .keep 101 none

def paid : Execution params environment :=
  executionOf start rotate1 13 reward first (by decide)
def paidAgain : Execution params environment :=
  executionOf first (.rotate 2 .keep 101 none) 14 reward second (by decide)
def unpaid : Execution params environment :=
  executionOf second (.rotate 3 .keep 101 none) 15 {} third (by decide)

/-- Local Checkpoint reachability, not composed Registry.SysReach or a chain tx. -/
def reachableStart : Checkpoint.Reachable params environment start :=
  ⟨0, [(0, .register 100 20)], (Checkpoint.T7_trace_iff_replay params environment).mpr (by decide)⟩
def reachableThird : Checkpoint.Reachable params environment third :=
  ⟨0, [(0, .register 100 20), (13, rotate1), (14, .rotate 2 .keep 101 none),
       (15, .rotate 3 .keep 101 none)],
    (Checkpoint.T7_trace_iff_replay params environment).mpr (by decide)⟩

def fundedTrace : FundingTrace params environment 0 start [reward, reward, {}] third :=
  .rotate (by decide) paid.lawful
    (.rotate (by decide) paidAgain.lawful
      (.rotate (by decide) unpaid.lawful (.nil 15 third)))

def event1 : Event := ⟨1, some 10, some 11⟩
def projected : ProjectedEvent params environment event1 :=
  { timing := ⟨10, 12, 12, 13⟩, execution := paid
    publication := rfl, available := by decide, chronology := by unfold ordered; decide
    inclusion := rfl, target := ⟨.keep, 101, none, rfl⟩ }

def modestCosts : Costs := { monitoring := 1, success := 2 }
def expensiveCosts : Costs := { monitoring := 1, success := 10, lockedCapital := 1 }
def submitAccount : Account := submissionAccount control 1 paid (by decide) modestCosts
/-- Named alternative: stop at this horizon, no cost and no service benefit. -/
def stopAccount : Account := {}
def lossAccount : Account := submissionAccount control 1 paid (by decide) expensiveCosts

def competitorPaid : Execution params environment :=
  executionOf start (.rotate 1 .keep 102 none) 13
    { hunter := some { addr := 102, pool := 10 } } first (by decide)
def competitorAccount : Account :=
  submissionAccount control 2 competitorPaid (by decide) modestCosts

def losingRace : Account := { costs := { monitoring := 1, failure := 2, racing := 1 } }
/-- An illustrative off-chain failed-attempt cost; no successful Step or new flow. -/
def raceRefused : Bool := (Checkpoint.stepFn params environment (.rotate 1 .keep 102 none) 14 first).isNone

/-- Fixed inclusion priority for agent 1; no randomness or equilibrium claim. -/
def raceGame : Game :=
  { agents := [1, 2]
    feasible := fun a => if a = 1 ∨ a = 2 then submissionMenu params environment event1 12 start (if a = 1 then 101 else 102) else [.stop]
    payoff := fun profile a =>
      if a = 1 then
        if profile 1 = .submit then utility submitAccount else 0
      else if a = 2 then
        if profile 2 = .submit then
          if profile 1 = .submit then utility losingRace else utility competitorAccount
        else 0
      else 0 }

def bothSubmit : Profile := fun a => if a = 1 ∨ a = 2 then .submit else .stop

def observeThenSubmit : Strategy := fun _ frontier =>
  match frontier with
  | .observed _ _ => .submit
  | _ => .wait

/-- Research-only motive/coalition; the underlying consecutive rotation is lawful.
There is no protocol predicate for useful vs manufactured valid work. -/
def manufacturedRevenue : Nat := rotationRevenue control 1 paidAgain.action paidAgain.flow

def manufacturePayoffs : Agent → Int
  | 1 => utility { revenue := manufacturedRevenue, costs := modestCosts }
  | 3 => utility { costs := { manufacture := 2 } }
  | 0 => utility { sponsorFunding := 10 }
  | _ => 0

/-- The same agent can fill controller and submitter roles. -/
def colludingControl : Control :=
  { control with roleOwner := fun role =>
      if role = .controller ∨ role = .submitter then 1 else control.roleOwner role }

/-- Constructive examples of invalid/unsupported observation, not confidence scores. -/
def hidden : Event := ⟨2, none, none⟩
def unavailable : Event := ⟨2, some 10, none⟩

def suppliedEvents : List Event :=
  [event1, ⟨3, some 12, some 13⟩, hidden, unavailable, ⟨9, some 30, some 1⟩]
example : frontierFrom suppliedEvents 14 = .observed 3 14 ∧
    sequenceLag first (frontierFrom suppliedEvents 14) = .behindBy 2 := by decide
example : frontierFrom [] 14 = .unknown ∧
    frontierFrom [hidden, unavailable, ⟨9, some 30, some 1⟩] 14 = .unknown := by decide
example : frontierFrom [⟨9, some 1, some 30⟩] 14 = .unknown := by decide
example : sequenceLag first (frontierFrom [⟨0, some 0, some 0⟩] 14) =
    .aheadOfObservation 1 0 := by decide

def mParams : History.Params := ⟨0⟩
def mEnv : History.TelEnv :=
  { signed := fun _ _ => true, receipted := fun _ _ => true, digest := fun t => t.i }
def inceptionWalk : History.Walk := ⟨⟨.vcp, 5, 5, 0⟩, ⟨⟨1, false, [⟨5, 0, 5⟩]⟩, 0, none, 0⟩⟩
def revocationWalk : History.Walk := ⟨⟨.rev, 7, 5, 1⟩, ⟨⟨2, false, [⟨7, 1, 7⟩]⟩, 0, none, 0⟩⟩
def issuerCheckpoint : History.Checkpoint := History.inception 1 0 0 none none
def mirrorRegistered : Mirror.Sys := Mirror.Sys.init.setCkpt 1 (some issuerCheckpoint)
def mirrorOpen : Mirror.Sys := mirrorRegistered.setReg 5
  (some ⟨1, 5, ⟨0, 0, 1, .provisional⟩, fun _ => false⟩)
def mirrorPushed : Mirror.Sys := mirrorOpen.setReg 5
  (some ⟨1, 5, ⟨0, 0, 1, .provisional⟩, fun said => said == 7⟩)

def mirrorReachable : Mirror.Reach mParams mEnv mirrorOpen :=
  .step (a := .register 1 0 0 none) rfl
    (.step (a := .open 1 inceptionWalk) rfl (.refl _))

example : Choice.submit ∈ submissionMenu params environment event1 12 start 101 := by decide
example : Choice.submit ∉ submissionMenu params environment hidden 12 start 101 := by decide
example : observeThenSubmit 1 .unknown = .wait ∧
    observeThenSubmit 1 (.observed 1 12) = .submit := by decide

-- Concrete premise witnesses and conclusions are checked independently of Claims.
example : isKeepRotation (.rotate 1 .deposit 101 none) = false := by decide
example : rotationRevenue control 2 paid.action paid.flow = 0 := by decide
example : paid.flow.dregIn = 0 ∧ paid.flow.bIn = 0 ∧ paid.flow.poolIn = 0 ∧
    paid.flow.refund = none := by decide
example : utility submitAccount = 7 ∧ utility stopAccount = 0 := by decide
example : utility lossAccount = -2 ∧ lossAccount.revenue = 10 := by decide
example : utility { principalReturned := 20, principalCommitted := 20 } = 0 := by decide
example : utility { principalCommitted := 20, terminalPrincipal := 20, costs := { lockedCapital := 2 } } = -2 := by decide
example : Checkpoint.stepFn params environment (.rotate 3 .keep 101 none) 15 second =
    some ({}, third) := by decide
example : eligible params 20 start = true ∧
    sequenceLag start (.observed 3 20) = .behindBy 3 := by decide
example : raceRefused = true ∧ utility losingRace = -4 := by decide
example : bestResponseB raceGame bothSubmit 1 = true ∧
    bestResponseB raceGame bothSubmit 2 = false := by decide
example : coalitionUtility [1, 3] manufacturePayoffs = 5 ∧
    coalitionUtility [0, 1, 3] manufacturePayoffs = -5 := by decide
example : colludingControl.roleOwner .controller = colludingControl.roleOwner .submitter := rfl
example : coalitionUtility [1, 1] (fun _ => 5) = 5 := by decide
example : observable hidden 100 = false ∧ observable unavailable 100 = false := by decide
example : sequenceLag first (.observed 0 12) = .aheadOfObservation 1 0 := by decide
example : sequenceLag first .unknown = .unknown ∧
    sequenceLag first (.unsupported 99) = .unsupported := by decide
example : projectionDelay event1 9 = none ∧ projectionDelay hidden 100 = none := by decide
example : projectionDelay event1 13 = some 3 := by decide
example : premiums [reward, reward, {}] = 20 ∧ paidCount [reward, reward, {}] = 2 := by decide
example : History.sealWalk mParams mEnv issuerCheckpoint 5 revocationWalk = some .provisional ∧
    Mirror.miss mirrorOpen 5 7 = true ∧ coveredB mirrorOpen 5 7 = false := by decide
example : Mirror.stepFn mParams mEnv mirrorOpen (.push revocationWalk) = some mirrorPushed := rfl
example : coveredB mirrorPushed 5 7 = true := by decide

def replenished : Checkpoint.State := .present ⟨2, 2, false, false, 0, 100, 10⟩
def afterReplenished : Checkpoint.State := .present ⟨3, 3, false, false, 0, 100, 0⟩
def topUpExecution : Execution params environment :=
  executionOf second (.topUp 10) 15 { poolIn := 10 } replenished (by decide)
def renewedPaid : Execution params environment :=
  executionOf replenished (.rotate 3 .keep 101 none) 16 reward afterReplenished (by decide)
def renewedTrace : FundingTrace params environment 0 start
    [reward, reward, { poolIn := 10 }, reward] afterReplenished :=
  .rotate (by decide) paid.lawful
    (.rotate (by decide) paidAgain.lawful
      (.topUp (by decide) topUpExecution.lawful
        (.rotate (by decide) renewedPaid.lawful (.nil 16 afterReplenished))))
example : premiums [reward, reward, { poolIn := 10 }, reward] = 30 ∧
    funding [reward, reward, { poolIn := 10 }, reward] = 10 := by decide

/-- No inclusion bound: a lawful rotate can occur at tick 100, with unchanged reward.
This refutes deriving promptness from legality or positive profit alone. -/
def latePaid : Execution params environment := executionOf start rotate1 100 reward first (by decide)
example : projectionDelay event1 latePaid.atTime = some 90 ∧
    utility (submissionAccount control 1 latePaid (by decide) modestCosts) = 7 := by decide

#eval ("supplied events -> frontier -> lag", frontierFrom suppliedEvents 14, sequenceLag first (frontierFrom suppliedEvents 14))
#eval ("no eligible data -> unknown", frontierFrom [hidden, unavailable, ⟨9, some 30, some 1⟩] 14)
#eval ("rewarded update: gross, utility", submitAccount.revenue, utility submitAccount)
#eval ("positive gross, net loss", lossAccount.revenue, utility lossAccount)
#eval ("exhausted pool still progresses", Checkpoint.stepFn params environment (.rotate 3 .keep 101 none) 15 second)
#eval ("mature and eligible but stale", eligible params 20 start, sequenceLag start (.observed 3 20))
#eval ("race: refused stale attempt, loser utility", raceRefused, utility losingRace)
#eval ("best responses under fixed priority: agents 1,2", bestResponseB raceGame bothSubmit 1, bestResponseB raceGame bothSubmit 2)
#eval ("manufacture: coalition; including sponsor", coalitionUtility [1,3] manufacturePayoffs, coalitionUtility [0,1,3] manufacturePayoffs)
#eval ("hidden, unavailable, chain ahead", observable hidden 100, observable unavailable 100, sequenceLag first (.observed 0 12))
#eval ("bounded example: delay; delayed inclusion counterexample", projectionDelay event1 13, projectionDelay event1 latePaid.atTime)
#eval ("pool budget: paid amount, paid work count, remaining", premiums [reward,reward,{}], paidCount [reward,reward,{}], third.poolHeld)
#eval ("renewed funding: paid amount, extra funding", premiums [reward,reward,{poolIn := 10},reward], funding [reward,reward,{poolIn := 10},reward])
#eval ("mirror covered before/after push", coveredB mirrorOpen 5 7, coveredB mirrorPushed 5 7)
#print axioms submissionAccount
#print axioms fundedTrace
#print axioms renewedTrace
#print axioms projected
#print axioms paid
#print axioms reachableThird
#print axioms mirrorReachable
#print axioms Checkpoint.T7_step_iff_stepFn
#print axioms Checkpoint.T7_trace_iff_replay
#print axioms Mirror.M10_freshness_unenforced
#print axioms CardanoKeri.Samaritan.self_fold_nonloss_iff
end Freshness.Examples
