# #291 — INV-BIND total KERI event decoding

Parent: #274

## Outcome

Every deployed checkpoint path obtains KERI event type and field boundaries by
totally parsing the submitted event bytes. No redeemer or evidence value can
choose where a validator reads `t`, `d`, `i`, `s`, `p`, `kt`, `k`, `nt`, `n`,
`bt`, `b`, `br`, or `ba`.

## Definitions

- A **caller offset** is any submitted integer or integer list used to locate a
  KERI field or value inside event bytes. Renaming or range-checking it does not
  remove the authority.
- A **total parse** consumes the complete 1–1024-byte canonical
  `KERI10JSON......_` serialization, checks its declared byte length, selects
  the exact `icp`, `dip`, `rot`, or `drt` field schema, and rejects malformed,
  duplicate, missing, unknown, reordered, escaped, or trailing framing.
- **Oracle offsets** may remain in committed keripy corpus metadata solely to
  state reference field spans. They are never encoded into a redeemer,
  evidence value, production decoder argument, or validator decision.

## Requirements

- **R291-001 — Bytes-only decoder.** One shared on-chain decoder and its
  Haskell parity mirror derive the complete establishment-event projection from
  event bytes alone. Parser failure is a validator rejection.
- **R291-002 — Close the class.** Registration, Advance, enforcement
  (Freeze/Convict), and hash-proof SAID blanking consume structure-derived
  fields. The acceptance boundary is every caller-offset-derived field read,
  not the instances reported in the issue.
- **R291-003 — Remove offset authority.** `RegistrationEvidence`,
  `AdvanceEvidence`, `EnforcementEvidence`, `HashProofRedeemer`, every off-chain
  mirror, and every live encoder contain no caller offset.
- **R291-004 — Preserve authentication.** Controller and witness signatures
  continue to authenticate the exact original event bytes. Existing datum,
  threshold, witness, SAID, and proof-token bindings remain enforced.
- **R291-005 — Keripy parity.** The decoder agrees field-for-field and
  variant-for-variant with the committed keripy 1.3.5 corpus, including `icp`,
  `dip`, `rot`, `drt`, weighted thresholds, witness sets, and witness deltas.
- **R291-006 — Pre-repair CAN-FAIL.** Every adversarial fixture is first run
  against the unfixed decoder and observed failing its rejection assertion for
  the intended legacy-acceptance reason. The grind exemplar is mandatory.
- **R291-007 — Framing mutation.** A single-byte mutation sweep covers every
  framing byte of every supported event shape and reports tested positions,
  mutants, and zero accepted malformed frames.
- **R291-008 — Bounded live rejection.** One time-bounded local-node
  transaction carrying the named malformed framing envelope is rejected. The
  same funding input remains unspent and checkpoint/proof-token state counts
  are unchanged; no positive product-state transaction is licensed.

## Spec-time invariant ledger

- **INV-BIND-291 (TIER-1 BLOCKING):** event type and every field boundary
  derive only from the event's own complete byte structure, never a caller
  offset. Failure means a submitter retains field-selection authority.
- **INV-TOTAL-291 (TIER-1 BLOCKING):** acceptance consumes exactly one
  canonical, length-consistent supported event with no unparsed bytes. Failure
  admits non-KERI bytes bearing selected substrings.
- **INV-TYPE-291 (TIER-1 BLOCKING):** registration/hash-proof accept only
  structurally decoded `icp`; Advance and enforcement accept only structurally
  decoded `rot`. `dip` and `drt` remain distinguishable rejection variants.
- **INV-ABI-291 (TIER-1 BLOCKING):** no deployed redeemer/evidence interface
  accepts a caller offset. Failure leaves the authority channel open even if a
  current call site ignores it.
- **INV-RED-291 (TIER-1 BLOCKING):** every adversarial fixture has mechanically
  captured pre-repair RED evidence. A fixture never observed failing proves
  nothing and cannot satisfy this ticket.
- **INV-PARITY-291 (BLOCKING):** both decoders match the keripy corpus on type
  and all protected field values. Failure is protocol drift.
- **INV-MUTATE-291 (BLOCKING):** every declared framing position has a
  non-vacuous one-byte mutant rejected by both decoders. Missing execution
  counts are failure.
- **INV-AUTH-291 (BLOCKING):** exact-event signature, datum, threshold,
  witness, SAID, and proof-token checks retain their existing negative rows.
- **INV-LIVE-291 (BLOCKING):** the named live envelope is rejected within the
  bound and changes no checkpoint or proof-token chain state.
- **INV-SCOPE-291 (BLOCKING):** unrelated discoveries are recorded for the
  parent census/backlog and do not expand this repair campaign.

## Five acceptance gates

1. Keripy parity corpus: all supported variants and protected values agree.
2. Adversarial CAN-FAIL: every named fixture is RED before repair and GREEN
   after repair, including a real `dip`/`icp` grind exemplar.
3. Single-byte framing mutation sweep: complete counted coverage, zero accepts.
4. No-offset interface audit: source census plus wire goldens prove removal.
5. Bounded live-node rejection: one malformed envelope, rejected with zero
   product-state delta.

All five gates plus repository CI must be green at the same candidate SHA.

## Submission and mutation stopping rule

Submission 1 is full-scope and must cover every invariant and all deployed
consumers. If its fresh auditor reports findings, submission 2 may change only
the generalized property classes named by that immutable report and is FINAL.
New unrelated findings go to the parent census/backlog.

## Output ceiling

This artifact is limited to 145 lines and 13 KiB.
