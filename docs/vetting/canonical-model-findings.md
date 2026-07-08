# Canonical Permissionless Model — Vetting Round 2

Independent re-vet of the **current** canonical permissionless model (2026-07),
replacing the archived `aid-ops.md` vetting. Two independent cold passes over the
normative docs (`architecture/`, `design/`, `design/business-cases/`, `roadmap.md`),
different primary lenses, then cross-examination and deduplication.

- **Pass A — soundness / permissionless attack surface**: [`analysis-2-soundness.md`](analysis-2-soundness.md)
- **Pass B — consistency / completeness**: [`analysis-2-consistency.md`](analysis-2-consistency.md)

Findings that both passes reached independently are marked **⋈ cross-confirmed** and
carry the highest confidence. Two Criticals (F1, F2) were additionally verified by the
orchestrator directly against the doc text.

!!! danger "Gates M1 implementation"
    Findings tagged **blocks #24** touch the `trie_key` / `KeyState` shape that #24
    freezes irreversibly at inception. They must be resolved before the identity
    key-state validator is written.

## Merged findings

| ID | Finding | Sev | Source | Blocks #24 |
|----|---------|-----|--------|:---------:|
| F1 | `trie_key` derivation is singleton (`cbor({cur_pubkey, next_digest})`) but the frozen shape is mandated **list-shaped k-of-n**; no list preimage defined; "1-of-1 degenerate case" is provably not the n=1 instance of any list formula | **Critical** | A·Q1/D10, B·C1/M1/M9 ⋈ | ✅ |
| F2 | Super-watcher **burn removes the leaf**, contradicting the "tombstone / registered at most once / never re-registered" invariant in three other docs | **Critical** | B·C2, A·D5 | |
| F3 | Emergency-freeze **reveals the pre-rotation next key without advancing `seq`** → converts a one-key compromise into a two-key compromise (non-atomic with rotation, unavoidable exposure window) | **Critical** | A·D2, B·C4 ⋈ | |
| F4 | Emergency-freeze **redeemer / `reveal_key` structure is undefined**, and `reveal_key` is not bound inside the signed `freeze_msg` | **Critical** | B·C3 | |
| F5 | `freeze_msg` has **no nonce/root binding** → a single ever-signed freeze is replayable as an attacker denial primitive | High | A·D2 | |
| F6 | Value-write `auth_msg` (Option A) **omits the freeze root** → a stale freeze-absence proof re-authorizes a frozen/stolen key (same-seq replay in the freeze window) | High | A·D4, B·H2 ⋈ | |
| F7 | Oracle can **censor** rotations/freezes and freeze-checking is **cage-optional** → oracle + `cur_key`-thief collusion keeps a stolen key economically live ("cannot forge" holds; "cannot keep alive" does not) | High | A·D3, B·O3 | |
| F8 | Super-watcher burn/bond presented as a convergence **guarantee** but unsound pre-Blake3 (script trusts extraction it cannot perform) and the challenge-period fallback has **no completeness or liveness** → innocent controller can be burned | High | A·D5, B·Q3/Q6 ⋈ | |
| F9 | Duplicity-freeze is **too narrow** (verifies both events against live `cur_pubkey`; misses forks under other/historical keys) **and a griefing/total-loss vector** (accepts any two distinct bytes under `cur_pubkey`, no KERI-structure/domain check → cross-protocol sig reuse permanently tombstones an innocent AID) | High | A·D6, B·H3 ⋈ | |
| F10 | Rotation redeemer **does not bind the signed `rot_msg`** to the `new_next`/`trie_key`/`seq_to` written to the resulting leaf → naive wiring lets an observer capture the identity at seq+2 | High | A·D1, B·M3 | ✅ |
| F11 | Deposit model contradictory: "protocol-defined **immutable** minimum" vs "controller-chosen **variable** convergence bond" — different validator logic and watcher incentives | High | B·C5, A·D5 | |
| F12 | `identity_root` used in two irreconcilable senses (single value in `inc_msg`/`auth_msg` vs sliding window); inception signature stales under concurrency; cage window-membership rule unspecified; typed inconsistently | High | B·H1 | ✅ |
| F13 | "Business pick only selects a last-mile adapter" is false — pilots need core components absent from M1–M3 (identified-pools registry, delegation-state UTxO, stake↔`trie_key` mapping, re-designation transition) | High | B·H7/O1 | |
| F14 | Reserved `delegator` field is **frozen into `trie_key`** but has no type/semantics/KERI-`dip` interaction defined — a meaningless value baked into an unretrofittable hash | High | B·H8 | ✅ |
| F15 | On-chain **feasibility/exec-budget** of the "bounded/O(1)" chain verification (4-hop ACDC + MPF proofs + Ed25519 + CESR) asserted, never budgeted; even the "cheap" per-action path unproven in Plutus V3 | Medium | A·Q2 | |
| F16 | **Ed25519 non-canonical-S malleability** unaddressed; breaks equality/replay checks keyed on signature bytes (incl. duplicity `event_1 != event_2`) | Medium | A·D7 | |
| F17 | Option A `auth_msg` **counter has no on-chain monotonic store**; root window + Praos rollback → cross-block replay | Medium | A·D8, B·L4 | |
| F18 | **Threshold/weighted-multisig well-formedness** entirely unspecified (zero weights, `threshold > sum`, empty sets, dup keys) → malformed, unrecoverable, possibly un-closable AIDs | Medium | B·M2 | ✅ |
| F19 | **TEL revocation registry (Layer 2)** required by every case but undesigned; simultaneously "unsolved" (amaru) and "ships M1" (roadmap #30) | Medium | B·M7 | |
| F20 | Two terminal fork mechanisms (super-watcher burn vs duplicity-freeze) with **different authorization/outcome/deposit** for overlapping offenses; needs one enumerated terminal-transition table | Medium | B·H4/M5 | |
| F21 | **Hop bound flips 3↔4** across docs; retired 3-hop diagram remains in `defi-gate.md` | Medium | B·M8 | |
| F22 | `cesr_aid` **Attack B** (squat a well-known AID with own keys) undefended; admission must never trust the stored `cesr_aid`/index, yet it is a first-class field | Medium | B·M4, A·Q4 | |
| F23 | **seq-0 binding** is off-chain/unenforceable; downstream claims assume SDK compliance; a hostile/buggy SDK → silent, whole-pre-rotation-life unverifiability | Medium | A·Q3 | |
| F24 | Missing normative **redeemer definitions** for Close, Duplicity-freeze, Emergency-freeze (only Inception/Rotation given); WASM carries proof fields the spec never lists | Medium | B·H6 | |
| F25 | `FreezeMarker.cur_pubkey_hash` is **dead data**; freeze-registry insert/replacement semantics undefined | Medium | B·H5 | |
| F26 | `KeyState`/status **restated in four docs** with drift; no `Diverged`/burn status enum value | Medium | B·M5 | |
| F27 | `amaru-integration.md` self-flagged **stale**, but its superseded oracle-writer claims live only there | Medium | B·M6 | |
| F28 | "Wait N blocks for root stability" vs **freeze urgency** — opposing mitigations never reconciled; freeze/rotation atomicity open | Medium | A·Q5, B·Q1 | |
| F29 | **`blake2b256-requirement.md` worked example is wrong** (43-char plain base64url instead of 44-char CESR qb64; contradicts its own "44 characters" and the bridge doc's warning) | Low | A·D9 | |
| F30 | `trie_key` **CBOR preimage not pinned** to the Aiken builtin byte-for-byte (map key type, field order) — gates the uniqueness / front-run argument | Low | A·D10 | ✅ |
| F31 | Naming/type drift: `POSIXTime` vs `Slot` validity; `counter` vs `nonce`; `inception_event` vs `cesr_inception_event`; window-depth constant only in prose; `op_hash`/`CageOp` under-specified | Low | B·L1–L4 | |
| F32 | Scoped-override / issuer freeze-seize power repeatedly flagged as contradicting the "cannot forge" headline but never designed (#40) | Low | B·Q5, A·OC1 | |

## Issues filed

Critical + High findings are tracked as issues (KERI / Work on the planner):

| F | Issue | | F | Issue |
|---|---|---|---|---|
| F1 | [#68](https://github.com/lambdasistemi/cardano-keri/issues/68) · blocks #24 | | F8 | [#75](https://github.com/lambdasistemi/cardano-keri/issues/75) |
| F2 | [#69](https://github.com/lambdasistemi/cardano-keri/issues/69) | | F9 | [#76](https://github.com/lambdasistemi/cardano-keri/issues/76) |
| F3 | [#70](https://github.com/lambdasistemi/cardano-keri/issues/70) | | F10 | [#77](https://github.com/lambdasistemi/cardano-keri/issues/77) · blocks #24 |
| F4 | [#71](https://github.com/lambdasistemi/cardano-keri/issues/71) | | F11 | [#78](https://github.com/lambdasistemi/cardano-keri/issues/78) |
| F5 | [#72](https://github.com/lambdasistemi/cardano-keri/issues/72) | | F12 | [#79](https://github.com/lambdasistemi/cardano-keri/issues/79) · blocks #24 |
| F6 | [#73](https://github.com/lambdasistemi/cardano-keri/issues/73) | | F13 | [#80](https://github.com/lambdasistemi/cardano-keri/issues/80) |
| F7 | [#74](https://github.com/lambdasistemi/cardano-keri/issues/74) | | F14 | [#81](https://github.com/lambdasistemi/cardano-keri/issues/81) · blocks #24 |

**#24 is now marked blocked-by #68, #77, #79, #81.** F18 and F30 also gate #24 but are
folded into F1/#68 (they are facets of defining the list-shaped preimage). Medium/Low
findings (F15–F32) are tracked in the table above pending triage, not yet filed.

## The two structural themes

Nearly every High rolls up into two root causes:

1. **The singleton↔list-shape split (F1).** The design ratified a list-shaped,
   threshold-capable, `delegator`-reserving `KeyState` and froze it into `trie_key`,
   but every derivation, message, redeemer, security argument, WASM signature, and
   `IntentTranscript` is still written for a single key. F10, F12, F14, F18, F30 and the
   whole "1-of-1 degenerate case" overclaim are facets of this. **This is the #24 gate.**

2. **The freeze/convergence channel (F2–F9, F11, F20).** Emergency-freeze, duplicity-freeze,
   and super-watcher burn are three overlapping mechanisms whose authorization, atomicity,
   replay-binding, tombstone-vs-remove semantics, and deposit disposition mutually
   contradict — and several are presented as guarantees while conceding they are unsound
   pre-Blake3. The recovery channel meant to save a compromised identity can worsen the
   compromise (F3), be replayed (F5), be bypassed by a stale root (F6), or permanently
   brick an innocent identity (F9).

## Method notes

- Both passes ran cold, without prior design intent, and were forbidden from reading the
  historical `aid-ops.md` vetting to avoid anchoring.
- The two lenses were assigned to reduce correlation; overlap (⋈) therefore indicates
  genuine independent rediscovery, not shared priors.
- No design docs were modified by this vetting — findings are recorded here and filed as
  issues; fixes are follow-up tickets.
