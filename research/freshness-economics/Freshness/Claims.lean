import Freshness.Examples

/-! PRIVATE PROPOSED STATEMENTS. Every theorem below is intentionally admitted.
Examples provide concrete model witnesses, not universal proofs or acceptance. -/
namespace Freshness.Claims
open Freshness CardanoKeri

/-- C1 — Submission versus stopping, not an equilibrium or promptness result.
Given protocol params/env and a lawful rotation e; control/agent/costs; a keep rotation with no refund change and an
explicit feasible menu containing submit and stop; and addressed premium
strictly above all submission costs. When comparing this submission with
stopping with zero payoff at this horizon. Then submission utility is strictly
larger. Model choices: linear utility, stop has no costs/benefits, no principal
movement in this keep-rotation comparison. Empirical: cost values. Protocol:
lawful Step, actual addressed Flow. Strategy: feasible alternatives.
Witness: Examples.paid/modestCosts, [submit,stop], premium10 > cost3, utility7>0.
Failure: Examples.lossAccount has gross10, cost12, utility -2. -/
theorem C1_submit_over_stop
    (p : Checkpoint.Params) (env : Checkpoint.Env) (control : Control) (agent : Agent)
    (e : Execution p env) (costs : Costs) (menu : List Choice)
    (rotation : isKeepRotation e.action = true)
    (submitFeasible : Choice.submit ∈ menu) (stopFeasible : Choice.stop ∈ menu)
    (margin : costs.total < (rotationRevenue control agent e.action e.flow : Int)) :
    utility (submissionAccount control agent e rotation costs) > utility ({} : Account) := by
  sorry

/-- C2 — Compose three separately justified bounds, never assume the total.
Given a ProjectedEvent with lawful exact-event rotation, publication and
available evidence at observation, ordered clocks and actual inclusion time;
observation≤publication+o, submission≤observation+d, inclusion≤submission+i.
When computing publication-to-projection delay. Then it exists and is at most
o+d+i. Model choice: discrete common clock and exact event target. Empirical:
observation and inclusion bounds. Strategy: decision bound. Protocol: Step.
Witness: Examples.projected, o=2,d=0,i=1; total3. Outside assumptions:
latePaid includes at100 (delay90); no rule forces an earlier inclusion. -/
theorem C2_delay_composition
    (p : Checkpoint.Params) (env : Checkpoint.Env) (event : Event)
    (projection : ProjectedEvent p env event) (o d i : Nat)
    (observationBound : projection.timing.observed ≤ projection.timing.published + o)
    (decisionBound : projection.timing.submitted ≤ projection.timing.observed + d)
    (inclusionBound : projection.timing.included ≤ projection.timing.submitted + i) :
    ∃ delay, projectionDelay event projection.timing.included = some delay ∧ delay ≤ o + d + i := by
  sorry

/-- C3 — Finite paid rotations in a restricted funded trace.
Given any p/env/time/start/end/flow list, a lawful FundingTrace consisting only
of rotations and topUps, a strictly positive premium, and initial pool plus
actual topUps at most an authorized budget. When counting positive rotation
premiums. Then total premiums≤budget AND paidCount*P≤budget.
Protocol: actual Step and Flow. Model choice: restricted trace, budget measures
premium expenditure only. Strategy: sponsor honors the funding cap. Empirical:
none for this accounting statement. No bound on unpaid progress or all costs.
Witness: Examples.fundedTrace, initial20 + topups0 ≤ budget20, P10, count2.
Outside cap: a lawful topUp allows further paid work; unpaid third still runs. -/
theorem C3_funded_work_bound
    (p : Checkpoint.Params) (env : Checkpoint.Env) (t : Time) (start finish : Checkpoint.State)
    (flows : List Checkpoint.Flow) (budget : Nat)
    (trace : FundingTrace p env t start flows finish)
    (positivePremium : 0 < p.P)
    (fundingCap : start.poolHeld + funding flows ≤ budget) :
    premiums flows ≤ budget ∧ paidCount flows * p.P ≤ budget := by
  sorry

-- Concrete antecedent witnesses are separate from the admitted claims.
example : Choice.submit ∈ ([.submit, .stop] : List Choice) ∧
    Choice.stop ∈ ([.submit, .stop] : List Choice) ∧
    Examples.modestCosts.total <
      (rotationRevenue Examples.control 1 Examples.paid.action Examples.paid.flow : Int) := by decide
example : Examples.projected.timing.observed ≤ Examples.projected.timing.published + 2 ∧
    Examples.projected.timing.submitted ≤ Examples.projected.timing.observed + 0 ∧
    Examples.projected.timing.included ≤ Examples.projected.timing.submitted + 1 := by decide
example : 0 < Examples.params.P ∧
    Examples.start.poolHeld + funding [Examples.reward, Examples.reward, {}] ≤ 20 := by decide

#print axioms C1_submit_over_stop
#print axioms C2_delay_composition
#print axioms C3_funded_work_bound
end Freshness.Claims
