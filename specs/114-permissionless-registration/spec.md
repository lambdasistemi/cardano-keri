# Reopen proposal #114: permissionless inception registration

**Target issue**: #114 (epic owner reopens; no new issue)
**Required base**: accepted #116 freeze-bond state revision
**Status**: RATIFIED by A-014; active on merged #116 + audit-fix base
**Design authority**: `/tmp/keri-24/permissionless-freeze-design.md` and
`/tmp/keri-24/verification-3-tickets.md`, A-014, A-015/A-016, and the
burn-axiom/audit-fix state merged through PR #130

## Purpose and dependency

#114 removes the obsolete anti-squat authentication layer from Register and
enables the bonded ACTIVE state defined by reopened #116. It lands after #116
and before #115. The delivered Register transaction shape, hash proof,
keys-must-match projection, fixed `d_reg`, and repeatable registration remain;
only the signature trust root and addition of `B` change.

#116's staging validator has Register fail closed. This ticket reopens the
mint branch only when the inception event's own public KERI signatures and
receipts authenticate the exact event bytes and the output posts the full
bonded value. Advance remains fail closed pending #115, so this intermediate
revision is not deployable.

## Scope

### In scope

- authenticate an `icp` with its own indexed controller signatures over exact
  `event_bytes`;
- authenticate its witness receipts over the same bytes and enforce `toad`;
- retain E1-E9 field projection and every existing Register R1-R6/R8 safety
  rule, renumbering only where the old fresh-signature rule disappears;
- delete the production `InceptionMessage` Cardano-domain signing layer,
  preimage generation, and private-key test signing helpers;
- require every fresh or repeated ACTIVE output to post at least
  `checkpoint_min_ada + d_reg + freeze_bond` lovelace and the quantity-one AID
  token;
- extend the keripy registration fixture family with real witnessed-inception
  receipts;
- preserve Haskell/Aiken parity, generated vectors, full-context tests, the
  live 21-theorem traceability gate, and a 25% measurement gate;
- ship a staged real-node E2E slice that proves every branch #114 opens and
  every branch it deliberately leaves closed;
- report the applied checkpoint program size and delta against both the
  19,565-byte #116 baseline and the 16,133-byte deployable budget at every
  slice gate; and
- update #114-owned registration narrative in the docs, M1 slides, and M1 blog
  in a pair-owned slice gated by strict MkDocs and lychee.

### Out of scope

- ARMED/FROZEN/Claim/Convict semantics (#116 base and the subsequently
  ratified burn-axiom handoff);
- Advance authentication or transition wiring (#115);
- Close/resolver (#117);
- any uniqueness registry, absence proof, mint-once rule, batcher, or
  sequencer;
- edits to historical issue specs. Documentation changes are limited to the
  #114-owned fragments named below and are never written by the orchestrator.

## Inherited Register transaction shape

The following delivered rules remain binding:

1. under the own policy, the complete mint map is exactly one pair whose name
   is derived from the datum AID and whose quantity is `+1`;
2. exactly one ACTIVE output carries that token and an inline well-formed
   `CheckpointDatum.V1` inception projection;
3. the datum is genesis (`seq=0`, native inception sequence) and its AID,
   key sets, thresholds, witnesses, and `toad` satisfy the frozen schema;
4. E1-E9 locate and compare `t/i/s/k/kt/n/nt/b/bt` in the exact keripy raw
   serialization, with bounds-first offset checks;
5. some input carries the exact hash-proof token named over
   `(event_bytes, cesr_aid)` and the transaction burns exactly that proof;
6. unrelated inputs and outputs are not globally rejected;
7. registration is repeatable, including after a prior checkpoint was
   convicted and burned; duplicate ACTIVE
   tokens are an admitted fail-closed, deposit-backed residual; and
8. both `d_reg` and `freeze_bond` are applied deployment parameters, never
   redeemer-selected values.

## Registration evidence and event-own authentication

`RegistrationEvidence` carries:

```text
event_bytes
off_t, off_i, off_s, off_k, off_kt, off_n, off_nt, off_b, off_bt
ctrl_sigs       : List<(index, raw_signature)>
wit_receipts    : List<(index, raw_signature)>
```

After E1-E9 and datum well-formedness:

1. each controller index addresses `datum.cur_keys`;
2. Ed25519 verifies its signature over exact `event_bytes`;
3. the distinct verifying positions satisfy `datum.cur_threshold`;
4. each receipt index addresses `datum.witnesses` and verifies over the same
   exact bytes;
5. the distinct verifying receipt count is at least `datum.toad`; and
6. when `toad == 0`, `wit_receipts` must be literally empty.

Bad indices and invalid signatures do not abort indexing; they simply do not
count, after which the threshold fails closed. Duplicate indices count once.
The literal-empty zero-witness rule prevents a malformed non-empty list from
being silently accepted as no evidence.

No signature covers a Cardano network, policy, output reference, deposit,
refund address, or reconstructed domain. Those facts are enforced by the
ledger context and applied validator. The KERI signatures establish that the
checkpoint faithfully projects public KEL material; they do not establish
that the transaction submitter is the controller.

## Removal of the fresh-signature layer

The live Register path no longer constructs, serializes, signs, or verifies
`InceptionMessage`. Remove its production type/helpers and the canonical-CBOR
preimage vectors that exist only for that layer. Do not reuse its frozen
domain string for a new meaning.

Tests generated from exported private seeds to sign a deployment-specific
message are removed. The already-exported keripy `event_sigs` become the live
controller evidence. Crossed network/policy signature negatives disappear
only because no such signed field exists; equivalent ledger transaction-shape
negatives remain.

This removal must reduce the net message/signing surface. Structural inception
schema helpers shared with datum validation may remain under names that do not
imply a Cardano authorization message.

## Bonded ACTIVE output and donation residual

The #116-applied `d_reg` and `freeze_bond` parameter predicates execute before
mint dispatch. Register requires the state output to hold at least:

```text
checkpoint_min_ada + d_reg + freeze_bond lovelace + exactly one derived AID token
```

The same minimum is mandatory for first registration, duplicate registration,
and post-conviction re-registration. Any surplus is carried by later
non-terminal transitions under #116/#115's conservative arithmetic. Fixture
values use `d_reg = 1_000_000_000` and a non-normative accepted `freeze_bond`;
deployed magnitudes remain operator choices above the #116 floors.

Both validators remain generic over deployment parameters. The inherited
mechanical floors are `d_reg >= 5_000_000` and
`freeze_bond >= 5_000_000` lovelace; fixtures and E2E use the
`d_reg = 1_000_000_000`, `freeze_bond = 5_000_000` reference pair. Each
parameter's one-below value rejects independently.

A third-party bridger is donating `D_reg+B` to checkpoint custody: it receives
no independent on-chain refund right. Only #117's ACTIVE-only, datum-key-signed,
challengeable close-intent flow can name the eventual refund. Held #117 uses a
distinct `W_close` deployment parameter and CLOSING role `0x03`; it never
reuses #116's `W_freeze`. This is what makes duplicate-bridge grief
victim-profitable without trusting historical keys at intermediate replay
positions. A bridging service must arrange compensation off chain.

## Duplicate and long-KEL behavior

There is no anti-squat signature because a bridge cannot exclude another
bridge. Anyone may register the public inception event and fund `D_reg+B`.
Consumers fail closed if supplied multiple ACTIVE references. After #115,
anyone may advance an old duplicate through the public KEL until its checkpoint
reflects current keys; after #117, a datum-key holder can open a challengeable
CLOSING `0x03` intent and name the refund. A false intent is directly voidable
by the ordinary next-event Advance in one transaction. An abandoned lagging
duplicate exposes `B` to #116's hunter flow. No global coordinator is needed.

## Normative anti-griefing invariants

Both lifecycle invariants are normative even though #114's deliberate staging
revision keeps Advance closed and remains **NO DEPLOY** until #115.

1. **Advance-totality.** In the completed stack, the same ordinary
   permissionless Advance MUST be admissible from every non-terminal role:
   ACTIVE, ARMED, FROZEN, and held-#117 CLOSING. #114 may neither consume nor
   mutate an existing sovereign checkpoint during Register, so a permissionless
   registration or re-registration cannot create a busy state that blocks the
   honest replayer's next Advance.
2. **Bounded adversarial interference.** An adversarial Register can only fund
   a separate checkpoint UTxO that faithfully projects the real signed and
   witnessed inception event. It cannot touch an existing checkpoint, invent
   a KEL state, or acquire a refund right. Duplicate ambiguity is fail-closed
   and deposit-backed, not same-UTxO exclusion. Across the completed machine,
   every adversarial touch must be real KEL progress, open an exclusive bounded
   window, or require an unavailable later-event/fork proof; touches remain
   O(1) per honest Advance, and a current checkpoint has no proof-free
   permissionless spender.

#114 vectors MUST prove Register never requires or consumes an existing
checkpoint input; duplicate/post-conviction registration produces an independent
state output; and adversarial submissions can project only the real inception
event. #115 owns Advance admissibility/real-next-event vectors, #116 owns the
arm-once/exclusive-`W_freeze` family, and #117 later owns direct CLOSING
Advance-void against intent spam.

## Fixtures and parity

The keripy fixture generator remains the oracle. For witnessed inception it
must export:

- exact inception raw bytes and all E1-E9 offsets;
- event-own indexed controller signatures over those bytes;
- indexed receipts by the inception witness keys over those same bytes; and
- only deterministic public test material needed to regenerate the fixture.

No Cardano-message signature is generated. The fixture suite proves every
exported signature target is `event_raw`, never SAID or reconstructed CBOR.
Haskell is the source for verdict and numeric vectors consumed verbatim by
Aiken; regeneration drift remains a gate.

## Required adversarial coverage

- witnessed, weighted, 2-key, 7-key, duplicate, and post-conviction Register
  positives at the bonded floor and with conservative surplus;
- a KERI event-own signature accepts while an old InceptionMessage-only
  signature rejects;
- controller bad index, bad signature, duplicate index, wrong key, crossed
  event bytes, and below-threshold sets reject;
- receipt-free witnessed inception, below-toad, duplicate index, bad index,
  wrong witness, bad signature, and `toad=0` non-empty evidence reject;
- all existing E1-E9 offset/misdirection, threshold, datum, mint-map,
  proof-input, proof-burn, output-count, token, and extra-input canaries remain;
- value one below `min+D_reg+B`, missing `B`, and redeemer-chosen parameter
  amounts reject for fresh and repeated registration;
- `d_reg`/`B` floors and one-below values remain generated and parity-checked;
- no registry input/output, absence proof, mint-once test, batcher, sequencer,
  or fresh-message signing helper remains;
- Advance remains explicitly fail closed pending #115.

## Lean-to-Aiken traceability

The checked-in `lean/traceability.csv` and its CI drift gate are binding input,
not #114 scaffolding. At each slice, the pair audits the 21 rows and replaces a
`PENDING(#127-pipeline)` sentinel only when that same commit adds the named
QuickCheck property and Aiken test required by the map. None of the currently
pending theorem rows is registration-only, so #114 does not force a sentinel
flip or import Convict/Reap lifecycle work merely to change the CSV. If a #114
slice genuinely makes a pending row executable, both mapped tests and the row
land atomically; otherwise all sentinels remain honest.

The map header remains honest: Lean proves the abstract model; QuickCheck
samples its pure Haskell mirror; generated parity vectors bind Haskell to
Aiken; and full-context Aiken tests cover ledger details the model abstracts.
No refinement proof is claimed. `just ci-offchain` must exercise the live
21-theorem/map gate at every green commit.

## Measurement gate

Measure the full Register handler, including hash-proof input/burn,
event-binding, controller event signatures, witness receipts, exact bonded
reserve, and final applied parameter arity, for at least:

1. 2-key unwitnessed inception;
2. witnessed 2-of-2 inception with 2-of-3 receipts; and
3. GLEIF-shaped 7-key inception.

Every row records raw memory/CPU, percentage used, and headroom. Any row below
25.00% headroom on either axis is a hard stop. Signer/receipt reduction,
fixture weakening, or measuring a pure predicate instead of the live handler
is forbidden.

Script size is a separate standing gate. The exact applied checkpoint program
is recorded after every slice, with `delta = current - 19,565` and
`budget margin = 16,133 - current`. #114 is allowed to remain over the budget,
but must retain the prominent **NON-DEPLOYABLE UNDER THE PRODUCTION CAP**
verdict in measurements, E2E output, and PR body. No deployment claim is
permitted. The deployability hard stop remains #115 mark-ready, with A-015's
binding remediation order: build-level first, then withdraw/observer
forwarding, and mint/spend split only after a fresh operator ruling.

## Staged live-node boundary

The existing `withDevnet` checkpoint harness is extended in a dedicated slice.
Against the real applied validator and real hash-proof policy it MUST:

1. settle the hash-proof mint and permissionless Register carrying
   `checkpoint_min_ada + D_reg + B`;
2. settle Arm against that freshly registered production-lineage checkpoint;
3. exercise Claim according to the actual #116 dispatch at the #114 head — a
   live branch is asserted positively, while an intentionally staged-closed
   branch is asserted as a Phase-2 rejection, never hidden as pending; and
4. prove Advance and Close still reach the production script and reject.

The existing devnet-only `maxTxSize = 32768` override remains single-field and
drift-checked, with the **NON-DEPLOYABLE** banner. This slice proves node
settlement and staging truth, not production-cap deployability.

## Pair-owned documentation slice

The #114 driver/navigator pair, never the ticket orchestrator, updates only
registration-owned fragments:

- `docs/architecture/veridian-bridge.md`, “Inception transaction”;
- `docs/design/trust-model.md`, registration/duplicate-bridge guarantees;
- `docs/blog/self-certifying-identities-on-cardano.md`, “Can someone register
  an identifier they do not own?” and the M1 registration availability bullet;
  and
- `docs/milestones-deck/index.html`, only the M1 registration speaker-note,
  key-state, and demo-registration fragments.

The narrative removes fresh Cardano possession/signing and “squatting
collapses to key theft”/“registered once” claims, explains event-own public
authentication, repeatable fail-closed duplicates, the posted `B`, and the
third-party-donation residual.

It also preserves the merged burn axiom: conviction history lives in the
transaction, not a permanent tombstone UTxO; conviction burns the checkpoint;
and a fresh registration remains admissible. It does not design or document
the later reap paths beyond the already-merged design-of-record handoff.

The theorem is a centerpiece in the #114-owned context: the M1 blog keeps the
central single-sovereign-UTxO argument, state machine, and per-move adversarial
table prominent and adds the permissionless Register row; `trust-model.md`
states advance-totality and bounded adversarial interference normatively; the
deck carries “anyone can project the public truth; no one can lie about it or
lock you out of it.” Every close mention uses CLOSING `0x03` and distinct
`W_close`, requires direct ordinary Advance-void, and rejects cryptographic
express-close; no line conflates it with `W_freeze`. The slice does not touch
normal Advance or freeze fragments owned by #115/#116 and runs the
repository-equivalent `mkdocs build --strict` and lychee gates after rebasing
on #116 docs.

## Acceptance criteria

1. Register is permissionless and accepts only event-own controller signatures
   and applicable witness receipts over exact `event_bytes`.
2. The fresh `InceptionMessage` authorization surface and private-key test
   signing layer are absent; frozen strings are not repurposed.
3. Keys-must-match, proof-token, threshold, datum, transaction-shape, and
   repeatable-registration rules remain live.
4. Every registration posts at least the fixed #116 `D_reg+B` reserve; no
   controller-selected parameter amount exists and surplus is conservative.
5. The two normative anti-griefing invariants and #114's distributed vector
   family hold: Register cannot touch an existing sovereign checkpoint and can
   only project the real witnessed inception event.
6. Haskell/Aiken verdicts, codecs, numeric boundaries, generated vectors, the
   executable 21-theorem traceability gate, full gate, and the 25% measurement
   gate pass.
7. The staged E2E settles Register+escrow and Arm, asserts Claim according to
   the actual dispatch, and proves Advance/Close remain fail closed.
8. The final size table reports bytes and deltas against 19,565 and 16,133;
   all artifacts remain prominently NON-DEPLOYABLE and #115 retains the hard
   stop.
9. #116 behavior remains unchanged and Advance stays fail closed pending #115.
10. The pair-owned #114 docs/slides/blog slice passes strict MkDocs and lychee;
   the two-invariant theorem is central and the orchestrator does not author
   those edits.
11. No historical spec, #117 code, PR-ready, or merge action occurs.
