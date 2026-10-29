# Freshness incentives — presenter brief

Meeting preparation, 29 October 2026. Research draft; no meeting decisions recorded.

## Opening in one minute

“We have an executable Lean protocol model and a separate research layer for your economic analysis. We want to study when someone has a reason to project available events promptly, and what freshness number we can honestly derive from observed data. The protocol supplies allowed transitions and payment rules; your work supplies the information, cost, competition and behavioral assumptions. We can express those assumptions and the resulting conditional claims directly in Lean.”

Introduce both obligations, then focus on the first:

- **Checkpoint freshness:** how far the projected key-event sequence trails the supported observed sequence, and how long a specific event takes to reach the chain.
- **Revocation-mirror freshness:** whether valid anchored revocations have been pushed into the mirror. A current checkpoint alone does not prove that coverage.

They can be studied separately. Their composition and independence are not proved in this draft.

## Show three examples

1. **Data to a number.** Supplied available event observations give sequence 3; the chain projects sequence 1: observed lag is 2. This is a comparison against the supplied observations, not a guarantee that no unseen event exists. Unknown observations stay unknown.
2. **Payment does not settle promptness.** A lawful update pays 10; illustrative costs of 3 give utility 7. Costs of 12 give utility −2. A late update can still earn a positive utility: profitability alone does not establish timely submission.
3. **Funding has a horizon.** A pool of 20 at premium 10 supports two paid updates. Further lawful unpaid progress remains possible; renewing funding changes the budget. The economic question is who keeps paying and what service they purchase.

Keep a fourth example available if useful: a controller and submitter may benefit from producing otherwise valid rewardable work. The draft illustrates a hypothetical coalition payoff; it does not establish a real exploit or a complete equilibrium.

## Show the Lean research interface

`Freshness/Concepts.lean` defines observations, sequence lag, delay, roles, costs, signed utility, lawful executions, feasible choices, a finite game, best response, coalition utility and funded traces. It imports the actual Checkpoint and Mirror models.

`Freshness/Examples.lean` executes illustrative cases. `Freshness/Claims.lean` contains three deliberately unproved proposals:

- **C1:** positive net submission reward beats zero-payoff stopping under its stated action and cost assumptions.
- **C2:** separately assumed observation, decision and inclusion bounds add up to a delay bound, conditional on an included event. This is not a liveness theorem.
- **C3:** a capped funding trace bounds total premiums and the number of paid updates.

All three use `sorry`. The examples compiled successfully; the universal economic claims are not proved. The scientist can change proposed research assumptions/types after discussion without treating them as accepted protocol changes.

## Ask for three outcomes

1. **Metric and evidence:** select sequence lag, publication-to-inclusion delay, or a conditional service target; identify observable data and hidden-event limits.
2. **Economic model and measurements:** choose actors, feasible strategies, information, costs, competition/inclusion assumptions and funding horizon. Identify what needs measurement rather than assumption.
3. **Next Lean deliverable:** revise one of C1–C3 into a meaningful conditional research claim, with a concrete positive case and a counterexample when a key assumption is removed. Assign its owner and the data needed.

Do not spend the meeting trying to finish proofs of weak or unreviewed statements. First agree what the statement should say.

## Preparation and meeting path

Before the meeting, allow roughly 25 minutes: read this page (5), inspect the three Claims docstrings and examples (10), and rehearse the opening and three questions (10).

Suggested 45-minute conversation: introduce both notions (5), walk through the examples and Lean interfaces (10), discuss assumptions and calibration (20), record the next claim/data/owner (10). The debrief template is intentionally blank.

The meeting does not depend on completion of #439 or compiled-validator verification. Those address consumer/implementation correctness; the present research discussion can use the pinned executable laws. Physical ledger correspondence, calibrated probabilities, dynamic equilibrium, guaranteed promptness and the Checkpoint–Mirror composition remain unestablished.
