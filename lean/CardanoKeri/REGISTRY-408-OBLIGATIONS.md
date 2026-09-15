# #408 obligations: what is proved, what is stated, what is owed

Record for the repaired registry candidate on `fix/408-registry-lifecycle`
(candidate sources: `RegistryAgreement.lean` sha256
`7e5a67aaa9288cb60e3f9888b2fcef1c38b9d38b5c6ba644a6424dfce4f3578e`,
`RegistryLifecycleExamples.lean` sha256
`538f62e9a7b1e9c6da2d514c086c38fa5c72be7f74e4745d1d3d7ecddca9036a`; the
eventual submission commit binds the final candidate). Base
27a7732efacf92ddfaf8dcbe61b000cfa7e194a0. Rulings binding this slice: A-002
(scope, custody split, budget), A-003 (universal-custody domain: explicit
`ReachFar` + `now < p.far`; arbitrary-Sys antecedent control), root NOTE-001's
CLOSED branch (lib11 closed the universal theorem — no universal owed row),
and root's verified axiom collection (below). The previous record's pasted
shell transcript and retired theorem names (`W3_revive_refused`,
`W3_key_still_pending`) are removed; the ruled W3a/W3b split supersedes them.

## Proved, with fresh axiom profiles

Axiom profiles are root's verified collection over the candidate
(`root0-final-axioms-v2`, exit 0, 50 declarations: 31 named theorems + 19
definitions; log sha256
`5e5393fa9408292f8b904c94872046d2427b86477844911ed64d5c2ca75ede90`;
profiles JSON sha256
`6750acbc6b192a1c1b36ac3efda65fd6393dbc2431d4c337586c9d85411b6df2`;
source bindings match the lib11 hashes above). Only `none`, `propext`, and
`propext + Quot.sound` occur. The lib11 build itself is sorry-free.
This is root verification of the candidate, not an independent audit verdict.

Collection history: the owner's first collector failed on a declaration-doc
comment before imports (receipt `repair0-axioms-final`, charged) and its
source was overwritten in place before archival — disclosed; it is not an
original retained file. Root's first collector failed on unsupported
`pp.width`/`pp.depth` options (receipt `root0-final-axioms`, charged); root
verified the supported options from the pinned Lean source before v2. Only
root's v2 collection (`root0-final-axioms-v2`, exit 0) is clean evidence.
Raw logs and receipts for both failures are retained; no reconstruction is
presented as an original archived file.

| declaration | says (Given/When/Then compressed; full types in the bundle log) | axioms |
|---|---|---|
| `Agreement.pending_go_preserved` | Given reachable `s`, `now < p.far`, `pendingGo s aid = some (.goDormant k)`; When ANY action succeeds except the fold processing the prestate's pending request (`consumesPending`); Then the successor keeps the same `pendingGo`. Refusal ⇒ no successor, no claim | `propext`, `Quot.sound` |
| `Agreement.refused_revival_keeps_leaf` | Given reachable `s`, leaf `dormant k`, a posted revive for `aid`, a fold processing it, refused; Then leaf still `dormant k` ∧ no checkpoint. Exact limit: concludes retained INPUT facts; the proof uses the retained-leaf hypothesis and R1c (`hpost`/`hb`/`href` unused) — no successor state exists, so this is not a temporal transition theorem | `propext`, `Quot.sound` |
| `Agreement.parked_leaf_no_ckpt` | Given reachable `s` and leaf `dormant k`; Then no checkpoint for that AID and the projection reads `.parked k` | `propext`, `Quot.sound` |
| `Agreement.custody_of_pending` | Given `pendingGo s aid = some (.goDormant k)`; Then the request rides in a real inbox entry (∃ witness) | `propext` |
| `Examples.W3a_contribution_keeps_pending` | Given the close journey up to the posted go-request; When a competing revive contribution is posted (before the close fold); Then the pending request is unchanged | `propext` |
| `Examples.preRefusedRevival_reachFar` | The W3b prestate (gen 2, close fold landed, revival posted) is `ReachFar` with explicit bounded slots | `propext` |
| `Examples.W3b_revival_fold_refused` / `W3b_refused_revival_keeps_leaf` | The revival fold at that exact prestate is refused (no rotation witness); after the refusal the leaf keeps dormant 1 with no checkpoint | `propext` |
| `Examples.W3b_positive_rotation_revives` (+`_journey`) | From the same prestate with rotation evidence the fold succeeds (leaf active 1, checkpoint live at key state 2). Positive fixture control, not a mutation kill | `propext` |
| `Examples.ant408_*` (4 claims) | A-003 antecedent control: in an arbitrary system the same retract succeeds at `now = 10 < far` and `pendingGo` is lost, and the system is proved not `ReachFar`. Establishes why the reachable-domain hypothesis is needed; does NOT test horizon necessity (no horizon-negative control exists) | `propext`; `now_before_far` none; `not_reachable` `propext, Quot.sound` |
| `Examples.W1_leaf_dormant` / `W1_no_ckpt` / `W1_bond_returned` / `W1_into_request` / `W1_reach` | Close story reached: register → fold → close (bond D to the premise-named recipient, go-request carries key state 1) → fold lands dormant 1, no checkpoint | `propext` |
| `Examples.W2_leaf_active` / `W2_ckpt_key` | Revival from exactly the retained state: fresh token, live checkpoint at key state 2, strict advancement | `propext` |
| `Examples.W4_wrong_recipient_refused` / `W4_no_premise_refused` | A live close against a recipient the premise does not name — or with no premise — is refused | `propext` |
| `Examples.W5_tomb_leaf` / `W5_no_bond_return` | Duplicity convicts the live checkpoint; the tombstone reaps permissionlessly (no premise, no bond return) and the fold lands the conviction | `propext` |
| helpers: `pendingGoIn`, `pendingGo_eq_pendingGoIn` (compiled bridge `:= rfl`), `consumesPending` (definition, axioms []), `pendingPred_cons_neg/pos`, `remove_absent`, `pendingPred_remove`, `pendingPred_applyBatch` | filter-head selector (filter predicate inlined verbatim from `pendingGo`; the compiled bridge holds by `rfl`), cons/remove filter lemmas (remove needs identifier uniqueness and a predicate-failing removed request), and the batch threading of the filtered-inbox invariant via `processOne_inv`/`rejectOne_inv` — a successful competing fold may process a foreign go-request, which those preserve | `propext` (+`Quot.sound` on cons/remove/applyBatch); `consumesPending` none |

An earlier draft helper (`accInv_remove`, claiming removal of ANY request
preserves `AccInv`) was deleted as false — `activeCkpt` is existential and
removing its very witness destroys it. The batch invariant is threaded only
through the existing post-operation boundary lemmas.

## The close-authorization boundary (accurate form)

The guard lives in `reapable`: a LIVE checkpoint is closable only when
`env.closeAuth aid recipient = true`, i.e. when the premise names the
recipient. `goOp` and `bondReturnOf` are not guards — they compute the
posted go-operation and the bond-return flow. At the theorem level:

- `R13_live_close`/`R13_close_conserves` take the TRUE premise as an
  explicit hypothesis (the close succeeds and conserves value GIVEN the
  premise names the recipient);
- `R13_live_needs_close_auth` takes the FALSE premise as an explicit
  hypothesis (the refusal direction);
- the `W4` statements are closed concrete examples (rfl computations over
  fixed environments), not theorems taking a hypothesis; their negative
  environment's premise is false for the requested AID/recipient, not
  necessarily a globally false oracle;
- `pending_go_preserved` and `refused_revival_keeps_leaf` quantify over an
  arbitrary `Env` with ReachFar/horizon/pending/success (resp. refusal)
  hypotheses and the consuming-fold exception — they take NO closeAuth
  hypothesis.

`closeAuth` is nowhere assumed globally. What #408 proves about the close is
value conservation only. What it may never prove (owner #358): that the
recipient is the owner, or that the reaper cannot be the recipient. The
former `quorum` oracle is known-wrong authorization (its own ticket rejected
it) and is not modelled.

## The observation boundary

Agreement with the checkpoint machine is judged at a **projection**
(`project`/`RegLife`), never step-by-step. A close is two raw steps and the
projection names the transit state. `Inv.activeCkpt`'s "checkpoint **or**
pending go-request" stays. Forcing `active-iff-checkpoint` at every raw step
would replace the registry's semantics with the checkpoint machine's.

## Semantic controls (production mutants) — executed on this candidate

Method: one compiled instrument
(`instrument-v3.lean`, sha256
`a05a78066ffee0806ef549bff245bd02f921b5181ef25e76721b47b1982bc72c`,
generator v3.1 sha256 in `instrument-v3.gen.json`, metadata revision
`instrument-v3.gen-meta2.json`) containing three namespace-isolated
source-derived copies of `Registry.lean` (Base verbatim; MutA/MutB with the
single-target edits below), no imports. The driver requires: positive
prestate checks (pending request 1 present with key state 1, generation 1,
`now < far`), competing-fold success evidence, baseline controls all pass,
and each mutant fails exactly its targeted control, with MutA successor-loss
demonstrated. Run `repair0-ctl-consolidated2`: exit 0, 22 CONTROL-PASS lines,
2 targeted CONTROL-KILL lines, MutA successor `pendingGo = none` observed;
log sha256 `5f7cbf427cde11574939f6987042298246e98dc9b9854844b13b1c3aa1ea7240`.
These are behavioral sensitivity results, not compiler REDs.

| control | class | result |
|---|---|---|
| MutA `stepFn.retract` drops `inPhase2` | pending-transition custody (retract boundary) | KILLED: the retract of the pending go-request succeeds, its successor `pendingGo = none` (loss demonstrated); competing-fold and close-premise controls still pass |
| MutB `reapable.live` drops the premise | live-close authorization | KILLED: the close succeeds without the premise; custody controls still pass |

Exact mapping of the earlier fixture controls to this table — the old rows
were fixture/observation edits and do NOT map one-to-one onto semantic
coverage of all claims:

- M1 (pendingGo ignores `userPostable`): a proof-shape failure — it
  establishes neither behavioral sensitivity nor unchanged behavior. MutA is
  a different production retract boundary (the `inPhase2` guard); it does
  not cover M1's selector question, and no supersession is claimed.
- M2 (W4 points at the premise-admitting environment): a fixture edit; its
  class (live-close authorization) is now covered by MutB.
- M3 (W5 drops the fold that lands the conviction): a fixture edit; its
  class (conviction transport) remains OWED — no semantic mutant exists.
- M4 (W3 observes the already-folded close): a fixture/observation edit; its
  class (pending custody) is now covered by MutA plus the universal theorem.
- M5 (`project` reads a parked leaf as present): a genuine semantic
  projection edit from the pre-repair campaign; retained as HISTORICAL
  evidence, not freshly rerun on this candidate.

Owed semantic classes (owner: the M1 desk, for allocation/reassessment in the
planned Singular slice where applicable — no tranche is authorized here):

- conviction transport: a semantic mutant letting a fold land a conviction
  without the tombstone reap (W5/13 must fail) — M3's class, still owed
- tombstone permissionless re-application after conviction
- batch-position coupling of the duplicity proof beyond 13's fork (R14 at
  arbitrary positions)
- horizon-necessity pair for `pending_go_preserved` (now ≥ far cases)

## Simulation corpus (regenerated from the committed driver)

15 retained IDs, 115 steps (extent guard intact); adopted close/revive
actions in 09/10/11/13/14, 12 repaired for its missing reap `recipient`
(retired two-field shape), 10's fork clock repaired; quorum replaced by
`closeAuth` rows (authorization input shape); slugs/narratives updated to the
adopted lifecycle with file names and IDs kept. Corpus:
`simulator/registry-simulator-corpus.json`, sha256
`1e90e334b9eda43b313f0ec47f812dab065eda5ac4b01e4b005a857f9c555308`,
byte-identical to the unchanged driver's output (receipt
`repair0-driver-regen4`). JSON/DSL agreement for all 15 pairs, step/branch
extent, and clock monotonicity verified by the persisted verifier
(`scenario-verify.cjs`, sha256
`23aef4f1a6187a830f8b6f2598a4b35839f09aecdb38fd3c1c81344d8e1d0fbf`).
Verified dimensions: canonical pairs, 15
IDs/115 steps, driver/corpus equality, per-step outcomes, normalized flows,
declared intermediate states, refusal state-retention, forward continuity,
cell/step binding, fork-prefix binding, carried clocks, finals, 4
instrumentation controls proven able to fire.

Unproved, stated plainly: refusal reason strings are NOT checked by this
Lean-driven verifier (Lean emits no reason strings); UI/core simulator parity
is not established (the page's embedded corpus and the core module are
outside this slice — no claim is made here about embedded page contents or
named refusal strings surviving a later UI repair). The verifier's
predecessor (verify5) overclaimed state coverage; verifier6 is the corrected
complete implemented check set.

## Historical note

The first independent audit's readback was non-blind and its actual matrix
was 12 PASS / 4 FAIL over 16 rows; no fresh independent verdict exists yet
for this candidate. The pre-repair mutation-campaign table ("five mutants,
all red") described theorem-level edits of the pre-repair candidate and is
retained only as history; its M-rows are mapped and relabeled above. The
accidental shell transcript previously embedded in this file is removed.

## Owed, with owners

| # | obligation | owner | note |
|---|---|---|---|
| 1 | semantic classes owed above (conviction transport, tombstone re-application, batch-position coupling, horizon-necessity pair) | M1 desk (allocation/reassessment; planned Singular slice where applicable) | budget-bounded; no tranche authorized |
| 2 | simulator seam: remove pause/resume from `registry-simulator-core.mjs`, rebuild the embedded page corpus, re-verify expectations | #408 simulator half | wider change, reported not performed; no claim made here about embedded page contents; retained legacy scenario filenames were required by the ruling — cosmetic naming can be assessed by the future owner |
| 3 | discharge `env.closeAuth` | #358 | downstream |
| 4 | registry integration | #324 | follows #358 |
| 5 | `Cage.lean` consolidation against Singular (Lake dependency choice settled; older Singular measurements historical) | slice 2 | Slice 0 remains dormant-without-checkpoint |
| 6 | missing implementation test layers (Lean↔Aiken vectors, off-chain) | implementation slices | unchanged |
