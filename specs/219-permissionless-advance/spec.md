# Spec: permissionless advance — authenticate rotation from the KEL (#219)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/219

Ratified inputs (do not reopen — parent Q-file required):
`specs/68-keystate-shape/spec.md` (frozen `CheckpointDatumV1`, F10 eq1-eq8,
dual-threshold rule), `specs/106-enforcement/spec.md` (`EventEvidence` slice
discipline, O1/O2), `specs/114-permissionless-registration/spec.md`
(event-own registration predicate, the E1-E9 event-binding discipline, the
ratified advance-totality invariant this ticket restores conformance with),
`specs/115-advance/spec.md` (`AdvanceMessage`, `advance_equalities` eq1-eq8,
W1-W3 witness delta, AE1-AE10 event binding, the ratified **QC** "no SAID
proof on the advance path" rationale this ticket's anti-replay argument
extends), commit `0f6a88c` ("refactor(114): authenticate inception events
from the KEL" — the direct precedent for this change), and operator ruling
A-005/2026-08-03 ("no asymmetry mess, M1 gets out clean").

Status: **ratified.** Q-001 (offchain parity-mirror scope) answered by
`A-001` — see "Resolved questions".

---

## Problem

Registration became permissionless in `0f6a88c`: a stranger holding only the
public KEL can register an identity, because the controller/witness
signatures in `RegistrationEvidence` authenticate the raw KERI `event_bytes`
directly, not a Cardano-domain message reconstructed from caller/context
data. Advance never received the equivalent treatment. Today:

- `onchain/lib/cardano_keri/checkpoint/advance.ak:74-100` reconstructs an
  `AdvanceMessage` (18-field Constr, `message.ak:115-134`) from the spent
  checkpoint, the proposed successor datum, and the evidence's witness-delta
  lists, then CBOR-serializes it (`advance.ak:270-271`,
  `cbor.serialise(msg)`).
- `advance.ak:272-274`: `ctrl_sigs` verify against that CBOR preimage — NOT
  `event_bytes` — with `NEW.cur_keys` at the signed index.
- `advance.ak:289-292` (V7): `wit_receipts` verify against `event_bytes`
  directly, exactly as the permissionless design requires.

The split is exactly the code's own module comment
(`advance.ak:40-44`): witness receipts are already event-own; controller
signatures are not. A signature over a preimage that embeds the exact spent
`TxOutRef` (and prior/successor sequence numbers) can only be produced by
someone who (a) holds the rotated keys and (b) knows, at signing time, the
exact UTxO the transaction will spend. Point (b) is what breaks
permissionless operation: **a relayer cannot relay, because it cannot re-sign
what it does not hold keys for**, and the key holder cannot pre-sign once and
let anyone submit, because a competing spend (a race, a witness board replay,
a retry after a dropped transaction) changes the UTxO and invalidates every
outstanding signature.

This contradicts the ratified advance-totality invariant
(`specs/114-permissionless-registration/spec.md`, "Normative anti-griefing
invariants" #1): *"the same ordinary permissionless Advance MUST be
admissible from every non-terminal role."* #115 amended `AdvanceMessage`
(the witness-delta rework) but never removed the message-preimage
controller-signing layer `0f6a88c` had already proven unnecessary for
registration one slice earlier. This ticket finishes that migration for
Advance, restoring conformance rather than changing the invariant.

## Scope

**In scope**

1. Move controller-signature verification (`advance.ak` V5) from the
   reconstructed `AdvanceMessage` CBOR preimage onto `event_bytes` directly
   — the same move `0f6a88c` made for registration's R7.
2. Delete the now-fully-dead `AdvanceMessage` Cardano-domain signed-message
   layer once nothing verifies against it: the type, `advance_domain`,
   `reconstruct_advance_message`, and the `AdvanceError` constructors that
   only ever fire against reconstructed-not-evidence fields (see "Anti-replay
   analysis" for exactly which ones are load-bearing vs. dead).
3. Restate the F10 checks that survive the deletion as direct `spent`-vs-
   `new` structural checks (no intermediate "message" object), mirroring how
   `0f6a88c` replaced `registration_message`/`validate_inception` with
   `validate_inception_datum` operating directly on the datum.
4. `specs/219-permissionless-advance/{spec.md,plan.md,tasks.md}` (this
   packet) recording the anti-replay design decision explicitly, with
   property tests proving it (both RED-first, per the TDD contract below).
5. `docs/user/rotate-preprod-identity.md` — rewrite "Why signing has two
   steps" to state there is one signing step (the native KERI `rot` event
   signatures, produced once by the controller and reusable by anyone who
   holds the public event + signatures). Note explicitly, in-doc, that the
   `ckeri advance --controller-signatures`/`--signing-package` CLI surface
   and `scripts/kli-sign-advance.py` are retired in a follow-up phase (#219
   phase 2, sequenced after #181), so the doc's procedural CLI section is
   marked provisional rather than deleted in this diff.
6. Haskell/Aiken parity for every changed predicate and regenerated vectors:
   `offchain/lib/Cardano/KERI/AID/Checkpoint/{Advance,Message}.hs`, their
   `{Advance,AdvanceFixtures,Message}Spec.hs` tests, `offchain/app/
   GenAdvanceVectors.hs`, and the goldens it regenerates under `onchain/`
   (never hand-edited) — ratified by `A-001` as constitutionally welded to
   the onchain change, distinct from the deployment/CLI surface below. No
   new keripy capture: consume the existing `advance.json` `rot_sigs`
   (`signing_target=event_raw`), mirroring `0f6a88c`'s `rcEventSigs` swap.

**Out of scope (phase 1 — re-briefed separately)**

- `offchain/deployment/Cardano/KERI/Deployment/{Advance,AdvanceTransaction}.hs`,
  `scripts/kli-sign-advance.py`, the `ckeri advance --controller-signatures`/
  `--signing-package` CLI flags: #181 owns the tx-building path; dropping
  this plumbing is phase 2, re-briefed after #181 merges.
- Any deployment or redeploy action. The preprod V1 redeploy, new manifest,
  and re-pin of live consumers (ckeri-follower, ckeri-query-preprod, producer
  witness boards) is a desk-arbitrated cutover. This ticket files a Q with a
  proposed cutover plan on acceptance; it does not execute one.
- Registration-path semantics (unchanged; the full existing suite is the
  regression gate).
- #220's surfaces (board resolution, KEL fetch).
- Delegated rotation (`drt`) admission — stays rejected (AE1), unchanged from
  #115.

## Anti-replay analysis (the design decision this spec records)

**Where anti-replay lived before this change, and what was actually load-bearing.**

`onchain/validators/checkpoint.ak:606-618` builds `SpentCheckpoint`
*exclusively* from validator parameters, the transaction's own named
`own_ref` (the actual spent `OutputReference` — a ledger fact, never
caller-supplied evidence), and `OLD` (the spent inline datum). Then
`reconstruct_advance_message` (`advance.ak:74-100`) copies fields from
`spent`/`new` 1:1 into the `AdvanceMessage` it builds:

| `AdvanceMessage` field | Source | `advance_equalities` check | Verdict on the wired path |
|---|---|---|---|
| `network_id`, `checkpoint_policy_id` | `spent.network_id`/`spent.policy_id` | eq1 | **tautological** — message field IS the spent field by construction; can never fail |
| `spent_txid`, `spent_index` | `spent.txid`/`spent.index` (= `own_ref`) | eq3 (`Eq3OutRefMismatch`) | **tautological** — same reason; this is the check the issue names as "binding the exact spent TxOutRef" and it is dead code in `advance_predicate` |
| `prior_seq`, `prior_native_sn` | `spent.seq`/`spent.native_sn` | eq4 (`Eq4PriorMismatch`) | **tautological** |
| `cesr_aid`, `aid_asset_name` | `new.cesr_aid`, `deriveAidAssetName(new.cesr_aid)` | eq2 | **real** — pins the created datum's AID to the spent one; prevents an advance from silently switching identities |
| `seq_to`, `native_sn_to` | `new.seq`, `new.native_sn` | eq5 (`Eq5SequenceMismatch`: `new.seq == spent.seq + 1 && new.native_sn > spent.native_sn`) | **real** — the actual state-machine sequencing invariant, checked between the two real datums, never routed through evidence |

So the "TxOutRef binding" the issue describes as the anti-replay mechanism
was never enforced by an on-chain equality (eq3 cannot fail in production);
it was enforced only by the fact that `ctrl_sigs` verified against a
preimage that *embedded* `spent_txid`/`spent_index` as signed bytes. That is
what actually coupled authorization to transaction context: the controller's
signature is over data that names a specific UTxO, so a fresh signature is
needed per attempt — not because the validator checks the binding
meaningfully, but because the signature scheme accidentally required it.

**What the deployed code actually enforces, versus what it appears to
check (ratified by A-001 as load-bearing).** Read `advance.ak`/`message.ak`
cold, the module comments and the `AdvanceMessage` shape strongly suggest the
`TxOutRef` binding IS the anti-replay mechanism — that is the issue's own
framing, and a fair reading of the code's intent. It is not what the code
*does*: the deployed validator's real, already-present anti-replay is eq5
alone (`new.seq == spent.seq + 1`, `new.native_sn > spent.native_sn`,
checked directly between the two real datums), plus AE1-AE10 pinning the
event's own fields to the created datum. The layer this ticket removes
carried authorization coupling (why a stranger cannot submit), not
anti-replay (why an old event cannot be replayed) — those are two different
properties that happened to share one signed preimage. Removing the layer
changes who can submit; it does not touch what already prevented replay.

**Where anti-replay lives after this change.**

Untouched by this change: eq5 (real, restated as a direct `spent`-vs-`new`
check with no message indirection) and the AE1-AE10 event-binding slice set
(`advance.ak:150-201`), which already binds the KERI event's own `s`, `k`,
`kt`, `n`, `nt`, `br`, `ba`, `bt` fields to the **created** datum — computed
from validated state, never caller-supplied, per the #106/#114 offset
discipline. In particular AE3 requires the event's `s` slice to literal-match
`respell_hex(new.native_sn)`.

The anti-replay argument is: a genuine KERI `rot` event has one fixed,
signed `s` (sequence number). AE3 pins that fixed value to the *proposed*
successor's `native_sn`, and eq5 requires that successor's `native_sn` to
strictly exceed the *actual* spent datum's `native_sn` (and its `seq` to be
exactly `spent.seq + 1`). A `rot` event already consumed to advance the
checkpoint from native_sn `N-1` to `N` cannot be replayed to advance a
*later* checkpoint (native_sn `M > N`) — AE3 would require its immutable
`s = N` to equal the new proposal's `native_sn = M+1`, which is false for any
single fixed event. This holds independently of which `TxOutRef` carries the
live checkpoint at each step: **a competing spend consumes the UTxO (ordinary
Cardano double-spend prevention) and does not need help from the
validator; the same signed event bytes remain valid authorization for the
one sequence step they attest to, for whichever transaction manages to spend
the correct prior-sequence UTxO first.** This is exactly the ratified #115
QC rationale restated for the controller-signature axis: *"strict sequence
monotonicity and AE1-AE10 pin the claimed rotation to the transition being
written"* — QC already treated the outref as incidental to identity/state
anchoring, not as the anti-replay mechanism; this ticket removes the last
place that outref appeared in signed evidence.

**Property tests proving this (RED-first, both halves; see TDD contract).**

1. **Permissionless-holds:** a party with only `event_bytes` + the KEL's own
   `rot`-event signatures (no Cardano-domain signing step, no knowledge of
   any `TxOutRef`) can produce evidence the validator accepts. RED on the
   current validator (which demands the `AdvanceMessage`-preimage signature
   it cannot produce without the controller's cooperation each time);
   GREEN after.
2. **No-replay-onto-later-state:** an event that already advanced the
   checkpoint from native_sn `N-1` to `N` cannot be reused to advance a
   checkpoint currently at native_sn `M >= N` to `M+1`. **Per A-001, the
   weakened variant must target eq5 itself — the mechanism that actually
   carries anti-replay — not AE3 or the message layer being deleted.** Prove
   the property RED against a validator variant where eq5's sequence
   monotonicity is weakened (e.g. `new.seq >= spent.seq` instead of
   `== spent.seq + 1`, or `new.native_sn >= spent.native_sn` instead of
   strictly `>`), showing the test can and does catch a real replay when the
   mechanism that prevents it is disabled; then prove it GREEN against the
   real, unweakened eq5.
3. **Competing-spend-preserves-authorization:** given one valid signed `rot`
   event and two candidate transactions racing to spend the same prior-state
   checkpoint UTxO, both transactions independently validate against the
   *same* evidence (the same `AdvanceEvidence` value with no txid-shaped
   field); only Cardano's ordinary single-spend rule decides which one
   lands. No evidence field or validator check may distinguish between them.

## TDD contract (mirrors the brief)

1. RED on current validator (permissionless-holds), GREEN after.
2. Anti-replay properties: RED against a deliberately weakened **eq5**
   variant (proves the property can fail for the stated reason — the real
   mechanism, not the layer being deleted), GREEN against the real,
   unweakened validator.
3. Full `aiken check` green as regression (registration untouched);
   Haskell/Aiken parity via `offchain/lib/Cardano/KERI/AID/Checkpoint/
   {Advance,Message}.hs` + their Spec tests + `offchain/app/
   GenAdvanceVectors.hs`, landing as one bisect-safe semantic swap with the
   Aiken change (`A-001` condition 1) — the drift gate must never be red on
   a landed commit.

## Acceptance criteria

- [ ] `ctrl_sigs` verify against `event_bytes` (mirrors registration's R7);
      the `AdvanceMessage` type, `advance_domain`, and
      `reconstruct_advance_message` are deleted, not repurposed.
- [ ] `Eq1NetworkPolicyMismatch`, `Eq3OutRefMismatch`, `Eq4PriorMismatch` (and
      their message-only fields) are removed with the message layer, not
      left as unreachable dead constructors.
- [ ] eq2 (AID continuity) and eq5 (sequence monotonicity) survive as direct
      `spent`-vs-`new` checks with no message indirection, byte/verdict
      identical to today's behavior on every existing positive/negative
      vector that exercises them.
- [ ] The permissionless-holds property is proven GREEN with a stranger
      construction (no Cardano-domain signing, no knowledge of `TxOutRef`).
- [ ] The no-replay-onto-later-state property is proven RED against a
      deliberately weakened variant (AE3/eq5 binding removed) and GREEN
      against the real validator.
- [ ] The competing-spend-preserves-authorization property is proven: the
      same evidence validates against either of two candidate spends of the
      same prior-state UTxO.
- [ ] Full existing `aiken check` suite green (registration, close,
      enforcement, freeze-bond, lifecycle-model untouched).
- [ ] `docs/user/rotate-preprod-identity.md` "Why signing has two steps"
      rewritten in the same diff; CLI surface marked provisional pending
      #219 phase 2.
- [ ] No deployment or redeploy action taken; a proposed cutover plan is
      filed as a Q on acceptance, not executed.

## Resolved questions

- **Q-001 -> A-001 (2026-08-03, desk).** Option 1 granted: the Haskell
  parity mirror is phase-1 scope (constitutionally welded to the onchain
  change), distinct from `offchain/deployment/**` + `scripts/
  kli-sign-advance.py` + the `ckeri advance` CLI surface, which remain
  forbidden/#181's/phase 2. Conditions: (1) the Haskell+generator+goldens+
  Aiken change lands as one bisect-safe semantic swap (or an ordered series
  that never breaks the drift gate); (2) the slice-gate writable-path fence
  is exactly the file list in "Scope" item 6 above; (3) the eq3/eq4
  tautology finding is recorded as load-bearing (done above — "What the
  deployed code actually enforces") and the weakened-variant RED property
  targets eq5, not the deleted layer (done above — property 2); (4) if the
  tautology analysis turns out wrong under test, STOP and file a fresh Q.
  On the separately observed Lean/"blaster" proof-target contract: desk
  altitude, not this ticket's — `plutus.json` changing under this ticket is
  expected and announced; this ticket's only duty is naming the exact
  accepted commit, not pinning or coordinating baselines.
