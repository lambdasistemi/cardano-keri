# Feature Specification: Genesis & registration package — decision record

Issue: https://github.com/lambdasistemi/cardano-keri/issues/91
Parent epic: https://github.com/lambdasistemi/cardano-keri/issues/21
PR: https://github.com/lambdasistemi/cardano-keri/pull/95

This is a **design-decision ticket**, not implementation. The deliverable is a
decision-record amendment to the canonical design docs
(`specs/68-keystate-shape/identity-model.md` §7a/§7c and
`specs/68-keystate-shape/system-architecture.md` §6/§9) plus a mechanical
decision-acceptance check. No validator, Haskell, wire-schema, storage-layout,
CESR-parser, adjudicator, or #24 lifecycle code is written here.

## Background — why the earlier conclusion is obsolete

The prior PR #95 stated that genesis **cannot be cryptographic** (§7a, spike #88)
and **cannot even be adjudicated on-chain** (both a true and a forged inception
are receipted by their own declared witness sets — "symmetric circularity"), so
the package engineered only attribution/teeth/time around a one-shot *attested*
event. Two merged evidence gates make that premise obsolete:

- **#97 / PR #98** (merged) landed the complete **32-byte** checkpointed BLAKE3
  path. A single BLAKE3 chunk (inceptions **≤ 1024 bytes**) is verified across an
  **8-block Step + 8-block Finish** transaction chain. Full spend-context worst
  case: Step **70.11 % memory / 73.54 % CPU**, Finish 68.44 % / 72.64 %, against
  the 14 M / 10 G mainnet per-tx budget. Two honesty caveats travel with it:
  (a) the figure **excludes** ledger→script `Data` deserialization of the
  ~1024-byte redeemer at the script boundary, so it is a **lower bound**, not the
  final cost; (b) it is a **multi-transaction** path whose intermediate chaining
  value must be authenticated — it explicitly **depends on #99**.
- **#99 / PR #100** (merged) restored the cage/thread-token security boundary: an
  oracle is **necessary but never sufficient** to manufacture AID authority or
  mutate another AID's leaf; owner authorization is checked against
  **authenticated** input/reference state; every mutated key is bound via
  `blake2b_256(owner_aid)`; a **real cardano-node Phase-2** proof settled a real
  `Modify`; the batch bound is **qualified, not a universal cap** (mainnet ≈ N=2
  at conservative declared budgets; ≈59 depth-0 handler estimate).

So `blake3(icp) == cesr_aid` is now an **on-chain-checkable predicate for the
single-chunk domain**, which dissolves the "symmetric circularity" argument
*there*. The ticket must re-aim on this evidence and **explicitly select**
cryptographic, attested, or deliberately hybrid genesis, and enumerate every
remaining trust assumption honestly.

## Decision (selected)

**Deliberately hybrid, on two independent axes.** Named precisely so no claim
overreaches the evidence:

### Axis 1 — the *byte binding* `blake3(icp) == cesr_aid`

- **Single-chunk inceptions (≤ 1024 B): cryptographic, on-chain.** Verified in
  Plutus via the #97 checkpointed Step+Finish chain, with the intermediate
  chaining-value state confined by the #99 cage/thread-token so an attacker
  cannot inject a forged mid-chunk value. This **cryptographically prevents
  cross-AID impersonation** for single-chunk inceptions: nobody can present bytes
  that hash to a victim's AID. This axis is **on-chain-decidable and autonomous**
  — no trusted party.
- **Multi-chunk inceptions (> 1024 B): attested,** pending a native `blake3`
  builtin (multi-chunk tree hashing is out of #97 scope). The oracle attests
  `blake3(icp) == cesr_aid` off-chain. Its fraud is **off-chain-recomputable**,
  **not** provable on-chain (see NOTE-004 boundary).

### Axis 2 — the *semantic projection* (stored key-state ⇄ CESR decode of the bound bytes)

Even with the raw inception bytes cryptographically bound (Axis 1, ≤1-chunk),
hashing does **not** prove the registry leaf's separately-stored
`(keys, kt, next_digest, witnesses, toad, native_sn)` is a faithful **CESR
decode/projection** of those bytes — unless an on-chain CESR projection check
runs. That check requires an on-chain CESR field extractor, which is **explicitly
out of scope** here (no CESR parser is authorized). Therefore:

- the projection is **attested at registration**, and
- policed by a **permissionless bonded challenge → mechanical on-chain freeze**
  (fail-safe; freezing needs no adjudication), with the **slash / unfreeze
  outcome authorized by an explicitly *trusted* governance key / k-of-n quorum**,
  informed by off-chain-reproducible recomputation over the on-chain-bound bytes.
  This is **not** a trustless Plutus fraud proof.

A fully-trustless projection fraud proof (an **on-chain CESR projection
verifier**) is named as a **deferred future hardening**, not this ticket.

### Activation timing

- ≤1-chunk: byte binding is proven on-chain at the Finish tx (immediate, no
  challenge needed for the binding). The leaf lands **provisional** for the
  projection: a challenge window Δ (governance parameter) precedes **activation**.
- >1-chunk: fully attested on both axes → provisional + full Δ + larger bond.

## Clarifications

### 2026-07-11 — NOTE-003 (semantic-projection boundary)

Q: Does the measured BLAKE3 fit make genesis fully trustless?
A: **No.** #97 binds the AID to the exact **raw inception bytes**; it does not
prove the stored key-state is a faithful CESR **projection** of those bytes. The
decision names the boundary as **cryptographic byte binding + attested /
challengeable semantic projection**. Projection fraud is **reproducible
off-chain** (deterministic decode over on-chain-bound bytes) but **not decidable
by the on-chain validator** in this ticket (that needs the deferred CESR
verifier).

### 2026-07-11 — NOTE-004 (adjudication / slashing boundary)

Q: If projection fraud is off-chain-reproducible, not on-chain-decidable, and has
no trusted adjudicator, how can a bond be mechanically slashed?
A: It cannot — those are contradictory. **Remedy selected: (b).** The on-chain
reaction is limited to a **permissionless bonded challenge that mechanically
freezes** the leaf (fail-safe, no adjudication). The **slash / unfreeze outcome
is authorized by an explicitly trusted governance key / k-of-n quorum**, using
the off-chain-reproducible recomputation as evidence. The bond's teeth are
**trusted-adjudicated, not a trustless fraud proof**, until an on-chain CESR
projection verifier exists. The same reasoning applies to the **>1024-byte
attested byte-binding fallback**: challenge/freeze is permissionless, slash/
unfreeze is trusted-adjudicated. The decision record must **not** describe
projection fraud or the >1-chunk attested digest as "objectively provable
on-chain" — only the ≤1-chunk byte binding is.

## P1 user story

As a cardano-keri protocol designer ratifying the identity model, I read the
amended `identity-model.md` §7c and `system-architecture.md` §6/§9 and find an
explicit, evidence-backed genesis/registration selection (hybrid: cryptographic
byte binding + attested/challengeable projection), with every remaining trust
assumption named and each capability claim matched to what the merged #97/#99
evidence actually supports — no obsolete "BLAKE3 cannot fit" premise remains.

## User stories

- **US1 — evidence-backed selection.** The record selects one model (hybrid) and
  explains why the measured #97/#99 numbers support it, replacing the obsolete
  premise rather than cosmetically rephrasing it.
- **US2 — honest boundaries.** The two boundaries (semantic projection per
  NOTE-003; adjudication/slashing per NOTE-004) are named explicitly; no claim
  says "objectively provable on-chain" where only off-chain recomputation exists.
- **US3 — enumerated trust.** Controller, witnesses, oracle/attester,
  challenge/fraud-proof, gating/censorship, slashing/bonds, activation timing,
  and what is / is not objectively checkable on-chain are each stated.
- **US4 — sibling consequences without absorption.** The record states the
  explicit consequences for #92, #68, and the #24 re-cut, and does **not**
  implement or re-scope those tickets.
- **US5 — mechanical acceptance.** A committed, executable check
  (`specs/91-genesis-registration/accept.sh`) fails on the pre-decision tree
  (RED) and passes on the amended docs (GREEN), so the decision content is
  bisect-checkable.

## Functional requirements

- **FR1.** `identity-model.md` §7c is rewritten to state the **hybrid** selection
  on both axes (byte binding: crypto ≤1-chunk / attested >1-chunk; projection:
  attested + challengeable), and §7a is updated so it no longer asserts the
  obsolete "genesis is not cryptographic" conclusion as current — it must reflect
  that #97 makes the ≤1-chunk byte binding on-chain-verifiable while the
  projection remains attested.
- **FR2.** The record names the **NOTE-003 projection boundary** and the
  **NOTE-004 adjudication remedy (b)** verbatim in intent: permissionless
  challenge/freeze on-chain; trusted-adjudicated slash/unfreeze; deferred on-chain
  CESR projection verifier as the trustless future.
- **FR3.** The record enumerates all remaining trust assumptions (US3 list) in a
  single, scannable place in §7c.
- **FR4.** `system-architecture.md` §6 and §9 are updated: decision 1
  (permissionless vs CF-gated) and decision 2 (MPFS-oracle vs token) are resolved
  **consistently with the hybrid decision and its shifted premise** — the
  mandatory-attester argument now applies to the *projection* (and >1-chunk
  binding), not the ≤1-chunk byte binding; the R-KEL note reflects the byte-binding
  reality. No decision is left asserting the obsolete mandatory-attester rationale.
- **FR5.** The record states explicit consequences for **#92** (storage/
  contention: the 2-tx genesis checkpoint chain, the #99-cage-confined
  intermediate state, provisional/active/frozen leaf states, the measured batch
  bound), **#68** (pin the inception CESR serialization + #97 checkpoint
  datum/redeemer shape + stored projection fields with Haskell/Aiken golden
  parity; flag on-chain projection verification as deferred), and the **#24
  re-cut** (base case becomes cryptographic byte-binding genesis + challengeable
  projection; attested residual for >1-chunk), **without absorbing** them.
- **FR6.** Capability language is honest: no generic-KERI interoperability claim
  and no production-readiness claim; the prototype framing is preserved. Links to
  the merged **#97** and **#99** evidence are present.
- **FR7.** `accept.sh` mechanically asserts FR1–FR6 (presence of the decision
  markers, absence of the obsolete conclusion, absence of any forbidden
  "objectively provable on-chain" claim attached to projection / >1-chunk
  binding, presence of the trust-assumption enumeration and the #92/#68/#24
  consequences, and the #97/#99 links). It fails on `origin/main` (RED) and passes
  on the amended docs (GREEN).

## Success criteria

- [ ] `./gate.sh` passes locally at HEAD before the PR is marked ready.
- [ ] `accept.sh` demonstrably RED on the pre-decision tree, GREEN after the slice.
- [ ] One bisect-safe decision commit carrying a `Tasks: T91-S1` trailer.
- [ ] PR #95 body and issue #91 no longer carry the obsolete premise and link
      #97/#98 and #99/#100.
- [ ] Fresh GitHub CI green; the PR-life `gate.sh` dropped before mark-ready.

## Out of scope (do not implement)

- Any validator, Haskell, wire-schema, or storage-layout code.
- An on-chain (or off-chain) **CESR parser / projection verifier** — named as a
  deferred future only.
- The **adjudicator / governance-quorum mechanism** implementation — named as a
  trust assumption only.
- The #24 checkpoint/pre-rotation lifecycle implementation, #92 storage model,
  and the #68 schema freeze — their **consequences** are documented, not their
  solutions.
- Modifying sibling ticket branches/worktrees or reverting merged #97/#99 work.
- #92 does not start until #91 merges (epic serialization).
