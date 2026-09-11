# Registry lifecycle repair (#408), Lean-only stage

Authority: issue408, adopted ruling12/D-039/D-040 as carried in issue359 and Checkpoint.lean; ticket408 A-001 and A-002 (M1 A-004/A-005). Original base a12af760e2cf3cf59059f30afe81cca746783070 is frozen.

As an identity holder I can leave a live checkpoint, retaining its reached key state for a later witnessed return with fresh bonds. As an observer I distinguish an actual parked registry hash from a checkpoint UTxO. As a prover I see the undischarged authorization obligation rather than mistaking it for established safety.

- INV408-01: no pause/resume edge, on-chain parked checkpoint, or grace window. Checkpoint juvenility is unchanged. Preserve live and tombstone transport states.
- INV408-02: live reap is enabled exactly under a plainly named abstract close-authorization premise supplied by Env; absent premise refuses. Never globally assume it. Every theorem using the premise exposes it as a hypothesis. Its recipient is opaque and parameterized. #358 owns discharging witnessed rotation and signed payee/refund binding; no authorization safety is claimed here.
- INV408-03: live reap burns/removes the checkpoint, retains the closing rotation's reached key state in the go-request, returns the live bond to the opaque recipient and conserves value. Existing request funding and min-ADA accounting remain explicit. Tombstone reap is immediate and permissionless with no live bond refunded.
- INV408-04: two-stage request/fold transport remains. Define the lifecycle projection in Lean; agreement with Checkpoint is at this projection/settled boundary, never every raw transport step. Keep Inv.activeCkpt's checkpoint-or-go-request disjunction.
- INV408-05: a parked registry leaf has no checkpoint; a pending request retains custody of the closing key state until folded. Neither reject nor retract may destroy a reachable go-request under the existing ReachFar horizon.
- INV408-06: return requires a witnessed rotation from exactly the retained key state and fresh bonds; the closing rotation itself cannot also revive. Conviction from retained parked state requires duplicity against its recorded key state. Convicted remains terminal.
- INV408-07: preserve request phases, uniqueness/token binding, plugin/generation restrictions, and Q-R3's unresolved retract signer status. No unrelated ruling or proof inventory redesign.
- INV408-08: changed public branches have exact success/refusal inversions, reachable antecedent witnesses, and effective compile-valid single-atom mutants. Completeness review precedes proof completion. Preserve existing compiled lifecycle zero-sorry and approved-axiom checks; both CardanoKeri and CardanoKeriStatements are built at declared Lean4.27.0.

Known-wrong env.quorum is rejected because issue358 itself identifies current-key theft and copied-payee attacks against that precursor. It cannot become an adopted rule by being described in an old ticket.

Tonight does not close full408: simulator/JavaScript, simulator/REGISTRY-LEAN-CLARITY.md and docs synchronization remain408 obligations. #358 authorization, #324 integration, #410 inventory/131-cause campaign and Q-R3 are excluded. No merge.
