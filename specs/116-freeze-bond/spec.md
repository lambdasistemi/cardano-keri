# #116: freeze-bond state machine

**Target issue**: #116 (reopened; no new issue)  
**Base**: `main` at `02e7fc7bead52418029319ee71335dd69093d4bd`  
**Status**: Ratified by A-014 — implementation in progress  
**Design authority**: `/tmp/keri-24/permissionless-freeze-design.md` and
`/tmp/keri-24/verification-3-tickets.md`

## Purpose and position in the stack

#116 owns the common state and value semantics needed by the two authentication
reworks. It lands first. #114 then enables bonded permissionless registration;
#115 then enables permissionless ACTIVE/ARMED/FROZEN Advance. No intermediate
revision is deployable; deployment is hard-blocked until #115 and then #117
are complete.

The #116 staging revision deliberately leaves Register fail closed and admits
no ARMED/FROZEN Advance. This avoids creating an under-bonded ACTIVE output or
an ARMED output whose response path is not yet delivered. Full-context #116
tests construct reserve-conformant synthetic state inputs to exercise Freeze, Claim, and
Convict. #114 and #115 remove those staging closures in their own scopes.

## Scope

### In scope

- add deployment parameters `freeze_bond` (`B`) and `freeze_window`
  (`W_freeze`) alongside `d_reg`;
- add ARMED role tag `0x02` and a versioned `ArmedV1` datum;
- define protected ACTIVE/ARMED/FROZEN reserves and conservative surplus
  arithmetic;
- replace direct ACTIVE -> FROZEN Freeze with ACTIVE -> ARMED;
- add permissionless ARMED -> FROZEN Claim at a hard deadline, paying `B`
  exactly to the recorded hunter;
- extend Convict to ACTIVE, ARMED, and FROZEN with exact `D_reg`/`B` routing;
- preserve the existing enforcement evidence binding, Freeze predicate,
  Convict predicate, tombstone record, re-registration rule, and self-convict
  residual;
- supply Haskell/Aiken parity models, generated vectors, full validator
  contexts, and measurements for #116-owned paths.
- update #116-owned freeze narrative in the docs, M1 slides, and M1 blog in a
  pair-owned slice gated by strict MkDocs and lychee.

### Out of scope

- Register authentication or enabling Register (#114);
- Advance authentication or ACTIVE/ARMED/FROZEN Advance (#115);
- Close and resolver behavior (#117);
- any registry, mint-once gate, shared root, batcher, sequencer, or oracle;
- changes to KERI enforcement evidence or conflict axes;
- every historical issue spec. Documentation changes are limited to the named
  #116-owned narrative fragments below and are never written by the ticket
  orchestrator.

## Parameters

The applied combined-validator parameter order becomes:

```text
version, hash_proof_policy, network_id, d_reg, freeze_bond, freeze_window
```

- `d_reg >= 5_000_000` lovelace remains unchanged and generic. Fixtures retain
  the non-normative `1_000_000_000` lovelace reference.
- `freeze_bond >= 5_000_000` lovelace is the proposed mechanical floor. It is
  high enough to form an independent enterprise-PKH payout UTxO. Its deployed
  economic magnitude remains an operator choice.
- `freeze_window >= 1` validity-range unit is the mechanical positive floor.
  `W_freeze` is configured from the operator's desired slot horizon, but the
  applied integer uses the same POSIX-millisecond units as Plutus
  `validity_range`; deployment performs that conversion once.

`W_freeze` is only the ARMED response window. Held #117 owns a separate
deployment parameter `W_close` for CLOSING; it is never inherited from or
implicitly equal to `W_freeze` (the expected deployment relation is
`W_close >= W_freeze`). #116 does not apply `W_close`.

Both value-floor predicates and the positive-window predicate run before mint
or spend dispatch. Haskell-generated vectors pin the floor, one-below, zero,
and ordinary fixture values in Aiken.

## Protected reserves and conservative surplus

| Role | Required checkpoint reserve |
| --- | --- |
| ACTIVE | at least `checkpoint_min_ada + d_reg + B` lovelace + 1 AID token |
| ARMED | at least `checkpoint_min_ada + d_reg + B` lovelace + 1 AID token |
| FROZEN | at least `checkpoint_min_ada + d_reg` lovelace + 1 AID token |
| TOMBSTONE | `checkpoint_min_ada + 1 AID token` |

`B` and `d_reg` are lovelace. Surplus is conservative: every non-terminal
transition retains the input's unrelated value in checkpoint custody. Arm and
ACTIVE/ARMED Advance preserve the complete input `Value`; Claim subtracts
exactly `B` lovelace and leaves every surplus unit on FROZEN; thaw adds exactly
`B` lovelace to the complete FROZEN value. #114 owns posting the minimum
ACTIVE reserve; #115 owns deterministic carry-forward/top-up arithmetic.

## Roles and armed datum

Existing encodings remain byte-for-byte:

```text
ACTIVE     bare script address
FROZEN     role tag 0x00
TOMBSTONE  role tag 0x01
ARMED      new role tag 0x02
```

`0x02` is new in the final role set; it does not resurrect REGISTRY. ARMED
carries:

```text
ArmedDatum = ArmedV1 {
  checkpoint : CheckpointDatumV1,
  hunter_pkh : ByteArray,  -- exactly 28 bytes
  deadline   : Int         -- validity-range time units
}
```

The wrapper constructor is the wire version tag; its `checkpoint` field is the
inner `CheckpointDatumV1`. The existing checkpoint bytes are unchanged.
ACTIVE/FROZEN still carry `CheckpointDatum.V1`; TOMBSTONE still carries
`TombstoneV1`. Haskell and Aiken codecs share generated CBOR goldens.
Role/datum mismatch, unknown constructor, bad hunter width, or invalid
deadline fails before redeemer dispatch.

## Deadline derivation and boundary

An arming transaction requires a non-empty validity interval with a finite
upper-bound endpoint `u`. The validator uses that attacker-pessimal endpoint
itself, without an oracle or a hunter-supplied clock:

```text
deadline = u + freeze_window
```

This anchors the response window to the arming transaction's upper validity
bound. #115's response Advance requires a finite upper-bound endpoint strictly
less than the stored deadline. #116 Claim requires a finite lower-bound
endpoint greater than or equal to the deadline. At the exact boundary response
rejects and Claim accepts. Empty or required-infinite bounds reject. Shared
Haskell/Aiken helpers cover just-before, exact, just-after, and unbounded
bounds; inclusivity flags never move the stored endpoint inward.

## ACTIVE -> ARMED (`Freeze`)

`Freeze { evidence, hunter_pkh }` is permissionless. It:

1. classifies an ACTIVE/V1 input with one derived AID token and at least the
   protected ACTIVE reserve;
2. binds the live evidence with unchanged EE0-EE9 rules;
3. runs the unchanged witnessed-later-event Freeze predicate;
4. checks `hunter_pkh` is 28 bytes and derives the hard deadline from the
   transaction interval and applied `W_freeze`;
5. creates exactly one ARMED output with unchanged inner checkpoint datum,
   recorded hunter/deadline, and the complete input `Value`; and
6. mints or burns nothing under the checkpoint policy.

Direct ACTIVE -> FROZEN is deleted. ARMED and FROZEN cannot be armed again.

## ARMED -> FROZEN (`ClaimFreeze`)

`ClaimFreeze { hunter_output_index }` is permissionless to trigger and needs
no KERI evidence or signatory. At or after the hard deadline it:

1. consumes one reserve-conformant ARMED/ArmedV1 input;
2. resolves the named transaction output and requires the enterprise
   verification-key address for the stored `hunter_pkh`;
3. requires that output to contain exactly `B` lovelace, no other asset, and
   no datum;
4. creates exactly one FROZEN output with the unchanged inner checkpoint
   datum and `input.value - B lovelace`, retaining every surplus unit; and
5. moves the AID token without policy mint/burn.

Early claim, wrong beneficiary/index, under- or over-payment, another asset,
datum-bearing payout, retained `B`, mutated checkpoint, wrong role, duplicate
FROZEN output, or own-policy mint/burn rejects.

## Conviction payout routing

The existing evidence binding, witnessed fork predicate, conflict axes, and
exact `TombstoneV1` record do not change. `Convict` gains a 28-byte
`convictor_pkh` and explicit output indices:

| Input | Exact tombstone | Dedicated payout outputs |
| --- | --- | --- |
| ACTIVE | min-ADA + token | `d_reg + B` to convictor |
| ARMED | min-ADA + token | `d_reg` to convictor; `B` to stored hunter |
| FROZEN | min-ADA + token | `d_reg` to convictor |

Each named payout is an enterprise verification-key output containing exactly
the stated reserved lovelace, no other asset, and no datum. ARMED's two indices are
distinct even if both PKHs or both amounts are equal, so one output cannot
satisfy two obligations. The tombstone remains exact; checkpoint surplus above
the protected reserves is unreserved and may leave as ordinary transaction
change on conviction. Extra unrelated inputs and outputs remain allowed.

Self-conviction remains benign: a forker may name itself as convictor, but an
ARMED hunter's `B` cannot be redirected, and the min-ADA/token tombstone stays
permanent for that token. Tombstone still bars no new registration.

## Staging dispatch matrix after #116

| Input/mint | Register | Advance | Freeze | ClaimFreeze | Convict | Close |
| --- | --- | --- | --- | --- | --- | --- |
| mint | fail closed pending #114 | n/a | n/a | n/a | n/a | n/a |
| ACTIVE | n/a | fail closed pending #115 | ARMED | reject | TOMBSTONE | reject |
| ARMED | n/a | fail closed pending #115 | reject | FROZEN | TOMBSTONE | reject |
| FROZEN | n/a | fail closed pending #115 | reject | reject | TOMBSTONE | reject |
| TOMBSTONE/unknown/malformed | n/a | reject | reject | reject | reject | reject |

This temporary fail-closed state is a dependency barrier, not final protocol
behavior. Mainnet deployment and #117 resume remain prohibited until #114 and
#115 remove the named closures and pass their gates.

## Required tests

- parameter floor/one-below and positive-window parity;
- reserve-boundary positives and one-below negatives, plus surplus-preservation
  positives for ACTIVE/ARMED/FROZEN;
- ARMED codec golden, role `0x02`, datum/role mismatch, hunter width;
- finite endpoint deadline derivation and response/claim boundary helpers;
- unchanged Freeze evidence positives and all existing EE/freeze negatives;
- ACTIVE -> ARMED state shape and direct ACTIVE -> FROZEN rejection;
- Claim exact payout and every beneficiary/index/value/time negative;
- Convict from ACTIVE/ARMED/FROZEN with exact record and payout routing;
- ARMED Convict distinct-index, hunter-redirection, and component under/over
  payment negatives;
- full role/redeemer matrix, terminal tombstone, repeated registration not
  used as an admission gate, no registry/batcher/sequencer symbol;
- explicit staging tests that Register and every Advance remain fail closed.

## Normative anti-griefing invariants

These are protocol obligations, not rationale. The final lifecycle MUST
satisfy both; #116 installs the state/window half while its fail-closed staging
revision remains deliberately non-deployable until #114/#115 land.

1. **Advance-totality.** Ordinary permissionless Advance MUST be admissible
   from every reachable non-terminal role: ACTIVE makes progress; ARMED is the
   response and retains `B`; FROZEN thaws after adding `B`; held #117 must add
   direct CLOSING Advance-void. TOMBSTONE alone is terminal. #116 therefore
   may not introduce an absorbing busy state: ARMED's datum/value shape and
   deadline helpers MUST be consumable by #115's ordinary Advance branch.
2. **Bounded adversarial interference.** Every adversarial state touch MUST
   either apply real KEL progress, open an exclusive bounded window, or require
   evidence the adversary cannot fabricate. Freeze requires a witnessed later
   event and can arm a given behind-state only once. Before its `W_freeze`
   deadline, ARMED admits no proof-free state change except the future ordinary
   Advance response; repeated Arm and early Claim reject. Claim needs genuine
   `W_freeze`-long absence, and Convict needs a real fork. Thus adversarial
   touches are O(1) per honest Advance, and a current checkpoint has no
   permissionless spender without a real next event/later-event/fork proof.

#116's adversarial vectors MUST cover arm-once-per-behind-state, repeat-Arm
rejection, early/exact/late boundary behavior, and the exclusive-window role
matrix. Until #115 opens Advance, staging tests record the reserved ordinary
Advance slot as fail closed rather than substituting another response action.

## Documented residual and #117 handoff

- **Third-party funds are donations.** A third-party bridger funds `D_reg+B`,
  and a third-party thawer may add `B`, but neither obtains an on-chain refund
  right. The held #117 close-intent path names the eventual refund, but a
  commercial bridge service still settles compensation off chain.

The verification discovered that immediate Close against mid-replay datum
keys would be unsafe: those keys can be retired historical keys. That finding
is not accepted as a documentation-only residual. Held #117 MUST add CLOSING
role address `0x03` with `{ refund_address, deadline }`, entered only from
ACTIVE by a datum-key-signed CloseIntent. Its deadline uses #117's distinct
deployment parameter `W_close`, never `W_freeze`; only an unchallenged intent
may later burn and refund `min-ADA+D_reg+B` plus surplus.

Advance-totality requires a direct ordinary permissionless Advance from
CLOSING that applies the real next KEL event, voids the false intent, and
returns ACTIVE in one transaction. A challenge-to-ARMED path may also exist,
but may not be the only void path. No cryptographic express-close or
pre-rotation-depth shortcut is admissible: co-leaked key chains prove neither
currentness nor safety. #116 adds no CLOSING, CloseIntent, FinalizeClose,
`W_close`, or Close dispatch.

## Pair-owned documentation slice

The #116 pair, never the ticket orchestrator, updates only the freeze-owned
fragments after the code and measurements are stable:

- `docs/design/trust-model.md`: lag/freeze state and incentive paragraphs;
- `docs/blog/self-certifying-identities-on-cardano.md`: “KERI can still move
  before Cardano”, lag-limit, and M1 freeze/bounty statements; and
- `docs/milestones-deck/index.html`: M1 speaker-note and lifecycle bullet
  fragments that currently say freeze is not bounty-paid.

The theorem is the slice's centerpiece, not a footnote. The M1 blog presents
why permissionless projection is safe on one sovereign UTxO, includes the
state machine and a per-move adversarial table, and makes advance-totality plus
bounded adversarial interference the central argument. `trust-model.md`
states both invariants normatively. The deck carries the exact one-liner:
“anyone can project the public truth; no one can lie about it or lock you out
of it.”

The edits also explain ACTIVE/ARMED/FROZEN, abandonment-only economics,
conservative surplus, permissionless response/thaw, and third-party donations.
Every close mention names held #117's distinct `W_close`, CLOSING `0x03`, and
required direct Advance-void; none implies that `W_freeze` protects Close or
that a cryptographic express-close exists. They do not rewrite registration or
normal-Advance fragments owned by #114/#115. The slice runs the
repository-equivalent `mkdocs build --strict` and lychee link gate.

## Measurement gate

Full final-handler contexts measure at least:

1. ACTIVE -> ARMED Freeze, 2-key;
2. ACTIVE -> ARMED Freeze, GLEIF-shaped 7-key;
3. ARMED -> FROZEN Claim;
4. ACTIVE -> TOMBSTONE Convict;
5. ARMED -> TOMBSTONE Convict; and
6. FROZEN -> TOMBSTONE Convict.

Every row records raw memory/CPU, used percentage, and headroom. Any result
below 25.00% headroom on either axis is a hard stop. Synthetic transaction
shape may supply reserve-conformant state values, but KERI evidence must remain the real
generated worst-case fixture and the measured target must be the full
validator handler.

## Acceptance criteria

1. `B` and `W_freeze` are applied, bounded parameters with cross-language
   parity; `W_close` is named only as a distinct held-#117 parameter.
2. ARMED is a new fail-closed role carrying the exact versioned hunter/deadline
   datum; old role and checkpoint bytes remain unchanged.
3. Freeze arms rather than freezes; Claim alone crosses to FROZEN and pays
   exactly the recorded hunter at/after the hard deadline.
4. Convict writes the unchanged exact tombstone and routes every `D_reg`/`B`
   component to the required dedicated recipient output.
5. Register and Advance are explicitly closed at the #116 staging revision;
   no under-bonded or unresponsive checkpoint can be created.
6. Advance-totality remains structurally possible and the #116 bounded-
   interference vectors prove arm-once plus the exclusive `W_freeze` window.
7. No unicity apparatus or off-chain ordering service is introduced.
8. Haskell/Aiken parity, generated vectors, full gate, and the 25% measurement
   gate pass.
9. The pair-owned #116 docs/slides/blog slice records the verified residuals
   and makes the two-invariant theorem its centerpiece; strict MkDocs and
   lychee pass, and the orchestrator does not author it.
10. No historical spec, #117 code, PR-ready, or merge action occurs.
