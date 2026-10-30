# Registry stories

Start with a request and process it into a live carrier. There is no owner exit: a carrier stays live until it is convicted. Conviction starts the only path out: pending custody, booking, then the consuming fold that retires the key. [Play the registry](registry-simulator.html).

These fifteen stable story IDs are the canonical Registry simulator stories; stories 9, 11 and 13 are retired (no owner exit) and keep their numbers. [M1-STORIES.md](M1-STORIES.md) remains the canonical M1 checkpoint story artifact; this catalogue does not replace it. Each story JSON carries the complete inputs and Lean-generated results; its DSL is an equivalent editable form. The player branches at refusals and preserves earlier nodes.

## Model and evidence boundary

The authority is `CardanoKeri.Registry.stepFn` with public Singular revision `d69ab005c3b710aeebf033d3c5cd08c56feb5643`. `registry-model-surface.json` binds the actual compiled dependency census and source bodies. `registry-simulator-clauses.json` binds the clauses below and each complete story input/result. The trace gate regenerates results without reading expectations. A displayed oracle match requires the exact parameters, evidence, action and starting state.

Evidence tables are finite model predicates, not signatures. Transaction assembly uses model fixtures and full observations, not a wallet. Registry key counters are not asserted to encode concrete checkpoint key states. Wire v3 preserves unbounded integers with JSON numbers in the safe range and canonical decimal strings outside it; arithmetic is exact. No production Aiken, Haskell, CLI transaction or deployed behavior is established by these stories.

Application Flow and economic transactions have different scopes. Registry conviction has an empty application Flow; the Checkpoint model separately records its addressed bond/pool payments. Generic rejection checks refund floors; it does not itself assert ledger fee/balance acceptance. Retraction and fold check their own specified economic conditions.

## 1. Alice books a registration

**Given** An empty registry and a complete registration booking.

**When** Alice posts its observed value, application tag, ready tag and interval.

**Then** The request is pending; no carrier or binding exists until a fold. A mismatched declared value is refused.

[Scenario](registry-simulator-scenarios/01-alice-requests.json) · [Editable DSL](registry-simulator-scenarios/01-alice-requests.dsl)

## 2. Hal delivers the first checkpoint

**Given** A pending registration and valid inception evidence.

**When** Hal spends the request and registry in a complete economic fold.

**Then** The destination receives the tagged carrier, the key becomes active, a token alias is allocated, and the generation advances.

[Scenario](registry-simulator-scenarios/02-hal-folds.json) · [Editable DSL](registry-simulator-scenarios/02-hal-folds.dsl)

## 3. Two folders race for one generation

**Given** Two folders have proposals for the same registry generation.

**When** One fold succeeds before the other is attempted.

**Then** The first delivery remains; the stale generation is refused.

[Scenario](registry-simulator-scenarios/03-folders-race.json) · [Editable DSL](registry-simulator-scenarios/03-folders-race.dsl)

## 4. A duplicate registration is refused and refunded

**Given** A key already has its first delivered carrier.

**When** A second registration is booked, attempted, then rejected with an authenticated lifecycle mismatch.

**Then** Booking alone cannot replace the carrier. Processing fails; rejection removes the duplicate request and pays its refund floor to its recorded address.

[Scenario](registry-simulator-scenarios/04-duplicate-registration.json) · [Editable DSL](registry-simulator-scenarios/04-duplicate-registration.dsl)

## 5. Alice retracts in the recovery window

**Given** A pending registration with a recorded refund address and submission time.

**When** The refund owner signs a complete transaction inside the retraction window.

**Then** The request is removed once and its full contents are refunded; ordinary funding pays the fee. An interval outside the window or missing signer is refused.

[Scenario](registry-simulator-scenarios/05-alice-retracts.json) · [Editable DSL](registry-simulator-scenarios/05-alice-retracts.dsl)

## 6. Sam rejects an expired registration

**Given** A registration remains pending beyond its processing and retraction windows.

**When** Sam reads the current registry and submits its expiry rejection.

**Then** The request is removed and the contents minus its tip reach the recorded refund address. The earlier expiry attempt is refused.

[Scenario](registry-simulator-scenarios/06-permissionless-sweep.json) · [Editable DSL](registry-simulator-scenarios/06-permissionless-sweep.dsl)

## 7. Empty and late folds are refused

**Given** A pending registration has a bounded processing window.

**When** Hal processes a nonempty batch within that window, or tries the empty/late alternatives.

**Then** The valid delivery succeeds; empty and out-of-window folds refuse without a successor state.

[Scenario](registry-simulator-scenarios/07-empty-fold.json) · [Editable DSL](registry-simulator-scenarios/07-empty-fold.dsl)

## 8. A fold preserves the pinned application

**Given** The registry fixes its application policy.

**When** A folder supplies that policy and registration evidence, or substitutes a different policy.

**Then** The correct fold succeeds; a substituted application policy is refused.

[Scenario](registry-simulator-scenarios/08-plugin-swap.json) · [Editable DSL](registry-simulator-scenarios/08-plugin-swap.dsl)

## 9. Alice parks and revives her retained output (retired)

Retired: there is no owner exit, so there is no parking and no revival. The number is kept; its disposition is in [registry-story-migration.json](registry-story-migration.json).

## 10. A live carrier cannot be swept into a termination

**Given** A live carrier retains its token, key and min-ADA, and nobody has convicted it.

**When** Sam tries to book it as a termination.

**Then** The booking is refused because only a convicted carrier can be booked. There is no owner exit to collect, and waiting creates no sweep entitlement.

[Scenario](registry-simulator-scenarios/10-sam-reaps.json) · [Editable DSL](registry-simulator-scenarios/10-sam-reaps.dsl)

## 11. Alice returns with the same token binding (retired)

Retired: there is no parked state, so there is no revival. The number is kept; its disposition is in [registry-story-migration.json](registry-story-migration.json).

## 12. Conviction becomes permanent through the consuming fold

**Given** A live carrier has duplicity evidence at its current key.

**When** Cora convicts it, Sam books its termination, and Hal processes that exact pending request.

**Then** Conviction preserves pending custody; booking moves the whole entry into the request and pays the defined premium. Only the consuming fold burns the token and permanently retires the key.

[Scenario](registry-simulator-scenarios/12-cora-convicts-bob.json) · [Editable DSL](registry-simulator-scenarios/12-cora-convicts-bob.dsl)

## 13. Cora convicts the parked output (retired)

Retired: there is no parked state; conviction of a live carrier is story 12. The number is kept; its disposition is in [registry-story-migration.json](registry-story-migration.json).

## 14. A pending termination has only the consuming fold exit

**Given** A convicted carrier has been booked into pending termination custody.

**When** Other parties try local moves or generic recovery before the actual consuming fold.

**Then** The pending request remains whole until the fold consumes it. Generic registration recovery is not a termination exit.

[Scenario](registry-simulator-scenarios/14-go-request-cannot-be-bricked.json) · [Editable DSL](registry-simulator-scenarios/14-go-request-cannot-be-bricked.dsl)

## 15. Batch inputs, timestamps and independent custody

**Given** Complete pending requests retain their own references and custody.

**When** A folder processes selected requests, or tries duplicated inputs and inconsistent timestamps; the mixed-custody branch also interleaves another registration and refund.

**Then** Duplicate inputs and backdated booking refuse. Completing one identity preserves the other pending entry through the mixed fold and registration recovery; its own later consuming fold completes it.

[Scenario](registry-simulator-scenarios/15-batch-and-timestamps.json) · [Editable DSL](registry-simulator-scenarios/15-batch-and-timestamps.dsl)

## Earlier semantics

The migration ledger retains each earlier source digest and the disposition of its stable ID. Dormant registry leaves, revival requests and the timed sweep of parked output were retired by the retained-output model revision; parking and revival are retired by the no-owner-exit revision. Their old expected outcomes are not counted as current passing tests. Booking premiums apply only after conviction.
