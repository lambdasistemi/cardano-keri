# Scientist discussion and blank debrief

**Research discussion draft, 29 October 2026. No meeting outcomes recorded.**

## Open with the two freshness obligations

A checkpoint projects a key-event sequence. `Freshness.sequenceLag` compares its
sequence with a supported observed frontier, distinguishing unknown, unsupported,
missing projection and chain-ahead observations. `frontierFrom` filters a supplied finite Event list at the sample time and takes
the maximum eligible sequence; no eligible events yields unknown. Future
publication, future evidence and unavailable entries do not contribute. The
data-to-number example yields observed seq3 at tick14, then lag2 from chain seq1.
A zero observed lag does not
rule out hidden events or events published after the sample. `Event.publishedAt`
and `evidenceAt` are distinct: publication without available evidence need not
make submission possible. Times and sequence counts are different units.

`projectionDelay` measures time from publication to inclusion of an exact event;
unpublished events and reversed chronology yield `none`. `ProjectedEvent` binds
that calculation to an actual lawful rotation of the event's sequence. This is
one checkpoint/lineage, modeled by sequence: byte identities, authentication of
observations and real clock alignment are not formalized in the research layer.
`Frontier.observed` is a supplied supported observation, not a proof that it is the
global latest sequence. No confidence probability is invented.

Mirror freshness is coverage of valid anchored revocations. `RevocationCovered`
reads the actual registry's revoked set; `MirrorComplete` quantifies over actual
revocation seal walks. `coveredB` is an executable check of a supplied SAID, not
an algorithm that discovers every revocation. Inception validity, provisional
versus final anchors, and consumer verification obligations remain in the
imported History/Mirror model; coverage alone does not replace them.

`CardanoKeri.Mirror.M10_freshness_unenforced` proves there exists a reachable
system with an anchored revocation for which the mirror still reports absence.
The examples reconstruct its register/open journey and then execute the actual
push. A fresh checkpoint is not a completeness proof for that set.

We focus economic work on checkpoints because their premium pool and addressed
rotation payment already exist. Mirror supplies a concrete second requirement,
not a second incentive project. Both depend on source publication, evidence
availability, observation, submitters and inclusion. The actual Checkpoint
lifecycle and the Mirror module's History checkpoint are different types; there
is no composition/refinement theorem connecting them in this package. We neither
assert full independence nor treat one as a substitute for the other.

## Imported facts and their limits

| Actual declaration | Use here | What it does not establish |
|---|---|---|
| `Checkpoint.Step.rotateKeepPaid`, `rotateKeepUnpaid`; deposit variants | Actual paid/unpaid law, via `stepFn` | Willing participants, observation or inclusion |
| `Checkpoint.T7_step_iff_stepFn` | `executionOf` turns successful execution into a Step witness | Real signatures or ledger acceptance |
| `Checkpoint.T7_trace_iff_replay` | Connected local register/rotate reachability | Composed `Checkpoint.SysReach`/Registry delivery |
| `Checkpoint.consumableStateB` | Existing consumer eligibility | Distance from latest off-chain state |
| `Checkpoint.Live.rotated` and Step rotation clauses | Birth time remains unchanged on ordinary rotation | Birth time as freshness timestamp |
| `Checkpoint.Flow`, `Payment`, `Params.premium` | Addressed premium from actual successful rotation | Ownership or allocation of unaddressed capital inputs |
| `Registry` (imported by Checkpoint) | Underlying delivered-origin/system boundary remains available | A constructed delivery receipt in these examples |
| `Samaritan.self_fold_nonloss_iff` | Existing addressed accounting, inspected and axiom-printed | Profitability of arbitrary freshness work |
| `Mirror.stepFn`, `miss`, `Registry.revoked`, `M10_freshness_unenforced` | Actual push/coverage and formal limitation | Mirror rewards, payment rules or completeness from checkpoint freshness |

`bornAt + W` is maturity. Example `start` is locally reachable, consumable at
tick 20 and three events behind its supplied observation. No need to alter the
accepted consumer predicate to exhibit that difference.

## What is proposed, and what is only assumed

Roles (`sponsor`, `controller`, `monitor`, `submitter`, `consumer`) are distinct
from controlling agents. Multiple roles/addresses can belong to the same agent;
coalition sums deduplicate agents. Address ownership is supplied, not proved by
an address number. Research choices (`monitor`, `submit`, `wait`, `withhold`,
`stop`, `manufactureValidWork`) are not protocol constructors.

`Account` uses signed integer utility. Revenue is separate from returned and
committed principal; returned 20 against committed 20 earns zero. Retained
principal has an explicit terminal valuation; locked-capital cost is charged
separately. This is a finite-horizon, face-value illustration with no discounting,
liquidity model or risk distribution. Cost fields cover monitoring, successful
and failed attempts, racing, capital and manufacturing. Fees are assumed inputs,
not chain measurements. Failed-attempt cost need not be a ledger fee.

`submissionAccount` requires a lawful **keep rotation with no refund change**.
Those actions have no `dregIn`, `bIn` or `poolIn` and no refund payment. Its account
is only the addressed premium less the supplied costs for that action; preexisting
capital ownership and lifecycle returns are not inferred. A deposit rotation may
need new B. It cannot be passed to this narrowed interface. Generalizing to it
requires explicit capital/funding attribution: Flow's inputs are unaddressed,
so the model cannot choose their funder for us.

The finite game has two active agents and a fixed priority rule. Its feasible
submission menus use publication/evidence availability plus the actual rotation
law. The payoff schedule remains an exogenous research choice; it does not model
a mempool. `Strategy` illustrates a policy from supplied observations, but the
normal-form table is not derived from an epistemic or dynamic game. `BestResponse`
and executable `bestResponseB` compare deviations in this table; no general
correspondence theorem, Nash equilibrium or coalition-stability claim is made.

The manufacturing example schedules otherwise valid consecutive events. It
adds a hypothetical controller cost of 2 to submitter cost 3 and reward 10:
coalition utility 5. Sponsor expense 10 makes the combined result −5. This expense
is the consumed premium, not the whole original deposit. The sponsor is outside
the profitable coalition in the first comparison. If one agent controls both
roles, combine its costs once. The example establishes neither real attack
feasibility nor anti-farming. It asks what distinguishes useful data production
from reward-seeking valid event production, and who finances each.

## Proposed claims for review, not proof completion

All quantified types, hypotheses and conclusions are in Claims.lean. Its docstrings
are the authoritative local Given/When/Then statements. No implementation layers
or accepted theorem corpus are claimed by these private proposals.

| ID | Given / When / Then | Concrete witness | Outside-assumption witness |
|---|---|---|---|
| C1 | Given p/env/control/agent, lawful keep rotation, costs, menu containing submit and stop, and addressed premium > total costs; when comparing action utility with zero-payoff stopping; then submission is strictly better | `paid`, `modestCosts`, feasible menu: 10−3=7 > 0 | `lossAccount`: 10−12=−2; paid `latePaid` still profitable at tick100 |
| C2 | Given `ProjectedEvent`, o/d/i, separate observation/decision/inclusion upper bounds; when computing publication delay; then some delay exists and delay≤o+d+i | publication10, observation12, submission12, inclusion13; bounds2/0/1 | `latePaid`: inclusion100, delay90; small inclusion bound fails |
| C3 | Given lawful rotate/topUp trace, positive P, initial pool+actual topUps≤budget; when summing premiums and counting paid work; then premiums≤budget and count×P≤budget | `fundedTrace`: P10, initial20, no topups, two paid and one unpaid | `renewedTrace`: topUp10, total30; old cap20 fails |

Assumption classes:

- **Protocol:** imported Step/Trace, monotone sequence guard, existing funding
  branches, exact addressed Flow, mirror seal-walk and push semantics.
- **Research/model choice:** common discrete clock; one lineage; supported
  observation labels; integer utility and horizon; external address control;
  zero-value stop; restricted rotate/topUp budget domain; fixed-priority table.
- **Empirical:** evidence/observation and inclusion bounds, actual costs, key and
  transaction availability. No empirical distributions measured here.
- **Strategy:** feasible actions taken on time, sponsor honoring a funding cap,
  collusion membership and motivation. Positive margin does not force submission.

Each claim has a concrete nonvacuity witness in Examples/Claims. There is no
universal real-world witness for observation or inclusion bounds. C2's typed
projection already supposes an inclusion exists; it proves no liveness or event
discovery. C3 bounds premium expense only, not monitoring fees, all sponsor loss,
total work or all lifecycle actions. P>0 is explicit: the protocol permits P=0.
Unpaid protocol progress remains possible when funded incentives stop.

## Calibration and decisions to ask the scientist

1. Which measurable service is purchased: sequence catch-up, publication delay,
   or a tail-latency target conditional on available evidence? What counts as
   publication, and which events remain invisible to a monitor?
2. Who can supply valid evidence and submit a paid rotate? Can it be copied or
   withheld, and what real authorization assumptions must replace our oracle?
3. What are monitoring, inclusion, failed-attempt, racing and capital costs,
   in common units and over what horizon? What behavior justifies a decision bound?
4. Who renews funding, what is the expenditure cap, and what service commitment
   survives exhaustion? Would subsidized unpaid submission be separately modeled?
5. Can controller and submitter manufacture valid rewardable work? Which costs,
   useful-service definition or alternative reward design should the next model
   compare? Any changed payment rule needs its own operator ruling first.
6. Should the next study retain fixed priority or add uncertain observation,
   inclusion and competition? Where would probabilities come from?
7. What bridge is required between the lifecycle checkpoint and History/Mirror
   before making a combined consumer guarantee? Who owns mirror push funding?

Suggested next research deliverable, subject to the meeting: one calibrated
checkpoint game with an explicit observation-to-strategy-to-inclusion mechanism,
three reviewed conditional statements, constructive failure cases, and a decision
on manufactured work. Proof work follows statement review. Mirror remains a
separate scoped follow-up unless the scientist selects it. Compiled-validator
verification can later check implementation behavior; it supplies neither an
economic equilibrium nor real-world observation/inclusion guarantees.

## Blank decisions and debrief — fill only after the meeting

- Meeting participants/date:
- Chosen freshness metric, source and unit:
- Accepted / revised / rejected assumptions (by ID or declaration):
- Required measurements, method and owner:
- C1 decision and changed premises, if any:
- C2 decision and evidence for each separate bound:
- C3 decision and authorized funding/service scope:
- Manufacturing/coalition question and chosen next experiment:
- Checkpoint–Mirror composition/funding boundary:
- Any proposed protocol change requiring operator ruling:
- Unresolved questions:
- Next research deliverable, owner and due date:
- Evidence/notes from the meeting:
