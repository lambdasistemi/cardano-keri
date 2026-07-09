# Identity model — KERI-sovereign, on-chain checkpoint, witnessed anchoring event

Status: **design decision, drillable.** Captured 2026-07-09. This reshapes #24, #68,
and #10, and refines `system-architecture.md` (identity key-state is now an on-chain
checkpoint, not a watcher-attested mirror). Open threads to drill are listed at the end.

---

## 1. The decision: identities are KERI-sovereign

There must be **no chance of forking an identity.** So an identity lives in the
**KERI / vLEI domain** — the witnessed KEL is the single source of truth — and Cardano
**anchors** it, never runs a second, independently-rotating copy. One state machine.
This retires the "two independent state machines" tension (and the divergence-burn that
policed it).

## 2. How Alice consumes her identity in a transaction (bring-your-own-proof)

Alice does **not** hold or spend an identity UTxO. Per gated action she carries a
self-contained proof:

- `cesr_aid` — her KERI AID (the opaque identity handle),
- `key_state` — her current keys revealed `[(pubkey, weight)...]`, threshold,
- an **inclusion proof** that `cesr_aid → commit(key_state)` is in the anchored
  checkpoint at `R_N`,
- **weighted k-of-n detached signatures** (Option A / #39) over the action,
- admission + non-revocation proofs,

and references, read-only (CIP-31), the **anchor UTxO** (`R_N`) and the admission-cache
UTxO. The validator checks: inclusion vs `R_N`, revealed keys match the commitment,
threshold signatures verify, admission + non-revocation, freshness. Because everything is
a **reference input**, identity use is inherently parallel — no identity-UTxO contention.

## 3. Why the key-state is an *incremental checkpoint*, not a KEL replay

A KEL is **unbounded** — no validator can replay it from inception. So identity is a
**checkpoint advanced one event at a time**: `state@seq N` + `rotation N+1` → validator
checks the single event against the current state → `state@seq N+1`. **O(1) per event**,
bounded. And only **establishment (rotation) events** change keys — interaction events
don't — so the on-chain cadence is *one tx per rotation* (rare), not per KERI event.

**This is exactly #24** (reveal pre-committed next key, check `hash(revealed)==next_digest`,
threshold sig, advance seq). #24 is therefore revived as the **integrity backbone**, not a
retired idea: the state only advances through validator-checked rotations, so no party can
inject fake keys — there is nothing to trust.

## 4. The special anchoring event that drives the checkpoint

For a **Blake3** (real vLEI) controller, Cardano cannot verify the native rotation event
(no `blake3` builtin). Resolution: the controller emits a **special anchoring seal** into
her own KEL — a **blake2b-SAID'd, witnessed** interaction/anchor event that carries a
**blake2b** commitment to the new key-state (reveal pre-committed next keys, commit the new
`next_digest` in blake2b), signed by the (new) keys.

- **KERI-sovereign** — the seal is in the one witnessed KEL; no separate machine, no fork.
- **Cardano-cryptographic without a builtin** — Cardano verifies the **blake2b** seal, not
  the Blake3 rotation. The invent-key-material hazard (§7) closes.
- **Ecosystem-compatible** — the native AID/KEL stays Blake3; the controller merely *adds*
  a blake2b seal. Far lighter than mandating blake2b digest agility on the whole `n` field.
- **KERI-idiomatic** — seals/anchors are native KERI; this is the "normative KERI
  checkpoint / event anchor" the original two-agent analysis (`system-discussion.md`)
  already recommended, re-derived from the integrity angle.

The controller must **emit** the seal per rotation — an SDK requirement in the same family
as the F-prefix work (#42). Cost: one seal + one Cardano advance tx per (rare) rotation.

## 5. Signature vs. witness — and why no-fork demands *witness*

What does Cardano check on the seal?

- **Signature-only** — that the controller's keys signed it. Proves *authorization*, but
  she can sign a **different** seal for the KERI world → Cardano and KERI **fork**. Trust
  bottoms out at *the controller not equivocating*.
- **Witness-receipted** — that the seal carries **threshold witness receipts**. KERI
  witnesses refuse to receipt two conflicting events at one sequence (duplicity
  protection), so the seal Cardano sees **must** be the one KERI sees → **no fork**. Trust
  bottoms out at *the controller's own witness set (honest threshold)* — exactly KERI's own
  assumption, no new trusted party.

**The no-fork decision (§1) forces witness-receipted.** Signature-only re-opens the fork.

Cost of witness-receipting: Cardano must (a) track the **witness set + witness-threshold**
as part of the checkpoint (they can change on rotation), and (b) verify threshold Ed25519
receipts over the seal's SAID — which requires the seal to be **blake2b-SAID'd** so Cardano
recomputes `blake2b(seal)==SAID` and confirms the receipts are over *that*. All builtins.

## 6. The checkpoint state (what the leaf holds)

The advancing checkpoint per `cesr_aid` holds more than keys:

```
Checkpoint {
  keys            : [(pubkey, weight)...]   -- current establishment keys (KERI k)
  threshold       : kt                       -- weighted k-of-n
  next_digest     : blake2b(next key config) -- pre-rotation commitment (blake2b)
  witnesses       : [witness_pubkey...]      -- current witness set
  witness_thresh  : nt-of-m                  -- witness threshold
  seq             : Int
}
```

Both the signing keys **and** the witness set advance through witness-receipted seals; a
witness-set change is itself a rotation whose seal must be receipted by the *old* witness
threshold (the mechanic to nail down — §"open threads").

## 7. What this settles: the integrity hazard

The sharpest residual risk was **forged key material**: a colluding watcher/SPO quorum
anchoring fake keys for `cesr_aid` (impersonation), which in the watcher-mirror model is
neither preventable nor punishable on-chain (both need Blake3). The on-chain checkpoint
**closes it**: the key-state advances only through **validator-verified, witness-receipted**
seals, so integrity is **cryptographic**, resting on the controller's own witnesses — not on
watcher honesty.

Corollary that refines "Blake2/Blake3 doesn't fork the system": it doesn't change the
*shape*, but it **does** change the *integrity model*:

| Path | Identity integrity |
|---|---|
| On-chain checkpoint via **blake2b seal** (this doc) | **cryptographic** — rests on the controller's witnesses |
| Watcher-**mirror** of native Blake3, no seal | **honest-majority-trusted** — the invent-hazard |
| Native Blake3 + a future Plutus `blake3` builtin | cryptographic (verify the KEL directly) |

## 8. Cascade — what changes elsewhere

- **#24** — *revived* as the incremental checkpoint (§3), now driven by witnessed seals.
- **#68** — the *frozen trie_key preimage* concern largely **dissolves**: Cardano mirrors
  the KERI key-state (shape is KERI's `k/kt/n/nt`), it doesn't derive a frozen preimage. The
  **weighted-threshold verification** (F18 rational-weight arithmetic) still stands — it's
  the sig check, not a frozen shape.
- **#10 (super-watcher)** — divergence-burn is **not needed** for identity forks (one
  machine). Its role shrinks to freshness/liveness of anchoring.
- **`system-architecture.md`** — R-KEL *for identity* is the on-chain checkpoint
  (cryptographic), not a watcher-attested mirror. R-TEL (credential status) remains
  watcher-mirrored — see the open thread below.

## 9. Freshness ≠ integrity

The checkpoint guarantees the on-chain state is **correct**, but not necessarily **current**:
there's a window between a KERI rotation and someone submitting the advancing tx. That's a
**staleness/liveness** knob (submission incentive + the freeze fast-path), separate from the
integrity the checkpoint provides.

## 10. Open threads to drill

1. **Witness-set rotation in the seal** — verifying a witness-set change: the seal must be
   receipted by the *outgoing* witness threshold; exact rule + edge cases.
2. **blake2b-SAID digest agility on the seal** — a blake2b-SAID'd event whose `p` chains off
   Blake3 priors; validate this is sound KERI and how witnesses receipt it.
3. **Credential-side integrity (R-TEL)** — identity is now cryptographic via seals; are
   credential issuance/revocation events analogously anchorable (issuer seals), or do they
   stay watcher-mirrored (trusted)? This is the parallel question for the credential plane.
4. **Freshness window sizing** — submission-liveness incentive + freeze fast-path vs the
   stolen-key window; per-use-case floor.
5. **SDK requirement** — the controller's KERI wallet/bridge must emit the seal per rotation
   (#42 family); who submits the Cardano advance tx (controller vs relayer/watcher).
6. **Who pays / contention** — per-`cesr_aid` checkpoint UTxO (ordered, no global
   contention) vs an MPFS checkpoint trie (aggregate root, batched writes).
