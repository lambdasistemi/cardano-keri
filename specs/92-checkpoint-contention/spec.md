# Feature Specification: R-KEL checkpoint advance-storage & contention model — the SOVEREIGN per-AID checkpoint decision (Candidate A, operator-ratified)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/92
Parent epic: https://github.com/lambdasistemi/cardano-keri/issues/21
PR: https://github.com/lambdasistemi/cardano-keri/pull/104

This is a **design-decision ticket**, not implementation. It resolves
`identity-model.md` **open thread 8** ("who pays / contention"): the **physical
storage and contention model for the identity R-KEL checkpoint advance path**.

#92's deliverable is a **decision + validator-shape sketch**: the ticket **selects
one physical model**, records the rejected alternatives and their residual risks,
and updates the canonical docs (`identity-model.md` thread 8,
`system-architecture.md`) with the decision. **That decision has now been made by
the operator** (`answers/A-001-thresholds.md`, ratified 2026-07-14): **Candidate A —
one sovereign, per-AID, quantity-one uniquely-tokenized checkpoint UTxO — is
selected.** This is a **normative security/product decision**; it is **not**
conditional on A beating B or C on a throughput/capital/cost score, and it does
**not** wait on ratifying arbitrary B/C measurement thresholds. This record no
longer keeps the storage shape "open pending evidence"; the operator decision
below supersedes that premise (NOTE-021).

The deliverable of *this record* is therefore (a) the boundary between the
**already-fixed logical** registration/unicity decision and the **now-decided
physical** advance-storage shape, (b) the **operator-ratified sovereignty invariant**
that selects A and the **explicit, sovereign reasoning** that rejects B and C, and
(c) the **Candidate-A implementation-sizing + live-boundary measurement plan** —
retained honestly as a **downstream implementation gate**, **not** as the reason A
was chosen and **not** invented here. No validator, Haskell, wire-schema,
storage-layout, CESR-parser, or #24 lifecycle code is written here.

## Operator decision — sovereignty selects Candidate A

The operator has selected **Candidate A** — each KERI AID's current-authority
checkpoint lives in its **own sovereign, per-AID, quantity-one uniquely-tokenized
UTxO** — as a **product/security architecture**, expressly **not** as the winner of
a throughput-cost contest. The load-bearing, **operator-ratified sovereignty
invariant** is:

> **Sovereignty / unrelated-AID isolation.** Unrelated issuers and attacker-created
> AIDs **cannot contend with, consume, serialize, or delay** an AID's
> current-authority checkpoint, rotation, recovery, or re-authorization path. Each
> AID's current-authority state advances **only** through its **own uniquely
> tokenized** `(checkpoint_policy_id, aid_asset_name)` UTxO; no other AID can spend
> or block it.

**Sovereignty and unrelated-AID isolation are the load-bearing selection criteria**
— not a cost/throughput matrix. The rejected candidates are rejected for **sovereign
reasons**, stated explicitly:

- **B is rejected** because a single/global/singleton MPFS checkpoint-root UTxO
  **serializes unrelated identities**. A shared global UTxO serializes unrelated
  identities: honest and hostile writers alike queue behind the same tip, so one
  AID's liveness depends on every other AID's write cadence. That is the opposite of
  sovereignty.
- **C is rejected** because its lane assignment `lane = f(cesr_aid)` is a **public,
  grindable** function: a permissionless attacker can grind AIDs until `f` lands in a
  **chosen victim's lane** and then spam it, and, more fundamentally, C makes an
  AID's sovereignty **depend on shard machinery** (K, `f`, re-shard migration)
  rather than on the AID owning its own state. Sovereignty that is contingent on
  shard parameters is not sovereignty.
- **A is selected** because each AID's current-authority state advances through its
  **own** uniquely-tokenized UTxO; unrelated AIDs **cannot** consume or serialize
  that state, so the sovereignty invariant holds **by construction**, independent of
  any throughput measurement.

**Measurements are retained as Candidate-A implementation sizing, not as the
selection reason.** Candidate-A **cost / transaction-size / min-ADA / batch fan-in**
figures and the **live-boundary smoke** remain **required** — but as **A's
implementation-sizing and live-boundary honesty**, a **downstream implementation
gate**. They are **not** the reason A was selected, are **not** selection evidence,
and **must not be fabricated, back-filled, or represented as the selection basis**.
The B/C **comparison** artifacts are **deferred / withdrawn honestly** (the operator
decision does not rest on them). This design ticket writes **no validators**; the
A-implementation-sizing prototype/measurement is a named downstream obligation, not
a precondition of this decision.

### Rotation and universal re-authorization

Sovereignty is the *isolation* property; **universal re-authorization** is the
*freshness* property the sovereign per-AID UTxO delivers:

1. **Normal rotation** consumes the current checkpoint UTxO and recreates the **same**
   token (`delta = 0`) with `seq + 1` and the new authenticated key state.
2. **The spent checkpoint is not available as a CIP-31 reference input.** Every
   still-pending protocol authorization made under the **prior** key state is
   **stale by construction** — it referenced a UTxO that no longer exists.
3. **Every future dApp action must resolve and reference the current checkpoint** and
   require the authorization envelope's **AID/key sequence to match the datum**, then
   verify the current weighted **threshold** over a fully bound action. There is no
   ambient "still authorized" state that survives a rotation.
4. **Cross-protocol lifecycle requirement** for long-lived objects: **Execute,
   Refresh/Re-sign, Cancel/Reclaim by the AID's current keys, and Expire/Cleanup.**
   "Re-sign by AID" is user language; the validator language is **re-authorization by
   the AID's current weighted key set at the current sequence**.
5. **Rotation does not erase bytes.** Pending authorizations become **powerless**;
   existing protocol state remains but its **next transition needs current
   authorization**; executed transactions remain history. **Value-bearing stale
   UTxOs need a current-AID reclaim path**, while off-chain or immutable metadata can
   only be marked **superseded/expired**, not reliably deleted.
6. **Distinguish this from historical credential evidence.** ACDC issuance / TEL
   seals remain **historical evidence** through issuer rotation until revoked — they
   are **not** pending dApp actions and are **not** invalidated by rotation.

### Indexer / discovery trust boundary (explicit)

Discovery uses a **generic Cardano multi-asset index**, and its trust boundary is
stated precisely:

1. Given the AID and network/protocol configuration, any wallet/proof builder derives
   the exact asset id `(checkpoint_policy_id, aid_asset_name)` and asks a **generic
   multi-asset index** for the current unspent output carrying it. The service may be a
   public indexer, a local chain-sync/node database, a wallet sidecar, or a replicated
   resolver — **not** a bespoke or authoritative QVI-owned AID directory.
2. **The indexer supplies location and freshness for liveness only. It never supplies
   identity truth or authority.** The consumer re-checks the returned UTxO against the
   ledger: exact policy/name and quantity one, accepted script address/version/lineage,
   well-formed inline datum, AID/sequence binding, and active/freeze/lifecycle rules.
3. **Plutus cannot query the global UTxO set by asset name.** The **off-chain resolver
   supplies the outref**; the **on-chain validator establishes truth from the real
   reference input** it is handed — the resolver's answer is only a pointer.
4. **A forged answer fails the boundary check.** A **cached/stale outref that rotation
   already consumed fails ledger validation** and triggers **refresh/retry**. An
   **unavailable/censoring indexer causes inability to construct the transaction
   (liveness), not false authorization**; clients need cache plus resolver failover or
   local chain-sync.
5. **Migration lineage and closed-state semantics.** A policy/script migration is
   discoverable through accepted protocol configuration and predecessor/successor
   lineage. **"No current asset found" fails closed for authorization**, while wallet UX
   must distinguish *never registered*, *explicitly closed/tombstoned*, *stale index
   data*, and *resolver outage* — without trusting the resolver's assertion alone.

### ACDC boundary correction

Any claim that a holder verifies an ACDC "signature under the issuer's authenticated
**current** keys" is **incorrect** and is corrected here. The ACDC specification
states that an ACDC is **not normally directly signed**; its **issuance or TEL state
event is sealed into the issuer's KEL**, binding it to the issuer **key state at that
historical state change** and **preserved through later key rotations** (its
verifiability is preserved through later key rotations):
https://trustoverip.github.io/kswg-acdc-specification/

The architecture therefore separates **three questions**:

- **Candidate A answers who controls/authorizes for this AID now** (the current
  sovereign checkpoint).
- **ACDC issuance-seal / R-TEL-R-ACDC evidence answers was this credential issued
  then, and is it still unrevoked now** (historical KEL/TEL evidence).
- **the dApp answers does that identity/credential authorize this action.**

The current checkpoint alone does **not** prove historical ACDC issuance, and KEL
replay is **not** reintroduced into every hot action. The **admission-cache split**
is preserved where appropriate: **historical credential-chain validation at
admission**; the **current-actor checkpoint plus admission/TEL status on subsequent
actions**.

### Emergency freeze (R-FRZ) — honest boundary + downstream residual

The existing **separate emergency-freeze mechanism (R-FRZ)** is preserved, with an
**honest statement of its contention/trust boundary**: a **shared freeze registry is
attacker-contendable** — it is not itself sovereign — and today's freeze path does not
inherit A's per-AID isolation. It is recorded here as a **downstream requirement**:
**the sovereign emergency path must not reintroduce a shared attacker-contendable UTxO.**
Re-cutting R-FRZ to a sovereign shape is **not** absorbed into #92; it is a
named **dependency/residual** on the #24 re-cut and the freeze-registry owner, not
silently implemented here.

### Batched dApp fan-in

Candidate A **removes the MPF inclusion proofs** B/C carry, but a transaction acting
on several AIDs at once needs **one CIP-31 reference input per distinct acting AID**
(each AID's sovereign checkpoint is read independently). The resulting
**transaction-size / ex-unit / live-node** cost of many-AID fan-in is kept as a
**Candidate-A implementation gate** (measured downstream, not fabricated here), not a
selection criterion.

### Loss / fork semantics and the superwatcher live-duty contract (reopen 2026-07-15)

*Normative for the live documentation.* After the first finalization the operator found
the loss/fork/superwatcher surfaces still carried the **retired
two-independent-state-machines / divergence-burn** framing (`docs/design/super-watcher.md`
kept a live convergence-enforcement body under a supersession banner; the loss/recovery
and fork/divergence user outcomes were unstated). This contract corrects it (**NOTE-022**);
the reviewed **DS6** documentation slice lands it across the live surfaces. The
sovereign per-AID checkpoint decision (Candidate A) is **unchanged** — this is a
**documentation-consistency correction**, not a decision change.

1. **KERI is the sole identity state machine.** The Cardano per-AID checkpoint is a
   **globally ordered, spend-linearized projection of current authority**, **not a second
   independently sovereign identity history**. For a witnessed AID, every advance requires
   threshold-receipted anchoring evidence, so a controller-only Cardano branch is rejected
   before activation; there is no V1 signature-only timeout fallback. The checkpoint can
   still lag. Witnessless AIDs and witness-threshold collusion are explicit weaker cases.
2. **Sovereignty does not eliminate synchronization lag.** When KERI rotates but the
   checkpoint has not been advanced or frozen, a **Cardano-only consumer still sees, and
   may accept, the old checkpoint key**. The old key is **stale in KERI** immediately, but
   **Cardano enforcement changes only when a successor checkpoint, an applicable freeze, or
   valid evidence reaches the ledger** — never "operationally stale everywhere immediately."
3. **A superwatcher is a first-class, permissionless cross-plane relayer and evidence
   submitter** — **not** a trusted oracle, identity authority, key custodian, backup
   service, recovery authority, or authoritative indexer. Ordinary KERI watchers police
   **intra-KEL** duplicity; a superwatcher spans **KERI ↔ Cardano** and the
   **credential-status (R-TEL) mirror**.
4. **Live duties (explicit).** Observe witnessed KERI events against the Cardano
   checkpoint; **relay** a fully witnessed anchoring transition when valid; **submit**
   objective duplicity or seal↔native-correspondence proofs; **request or trigger the
   applicable freeze path** when safe advancement is impossible; **police** stale/false
   R-TEL credential mirrors. Relay and freeze are permissionless; only a successful,
   irreconcilable-fork conviction is bounty-paid from the registration deposit.
   **A watcher never chooses truth when cryptographic evidence is absent.**
5. **Loss / recovery outcomes (kept separate).**
   - **lost local public KEL** — recover from KERIA / witness / watcher replicas; Cardano
     preserves a checkpoint/audit anchor but **cannot reconstruct the full KEL**;
   - **lost AID / OOBI or semantic locator** — exact-asset lookup works **once the
     qualified AID is known**, but Cardano does **not** guarantee recovery of the forgotten
     semantic identity mapping; wallet / contact / KERIA / witness backups own that
     availability;
   - **lost current private key with valid next/recovery material** — perform KERI
     recovery/rotation, then relay the checkpoint transition or freeze the old projection
     during the lag;
   - **lost current and all next/recovery material** — **no Cardano recovery exists in the
     current scope**; KERI superseding/delegated recovery is explicitly **out of scope**,
     so the AID is **unrecoverable/abandonable under this design**;
   - **witness-threshold collusion** — the KERI trust assumption has failed; a superwatcher
     may **expose and submit objective evidence** but **cannot manufacture a canonical
     truth branch**.
6. **Fork / divergence outcomes (kept separate).**
   - a witnessed advance (incoming `new_toad > 0`) **cannot proceed without the incoming
     set's threshold receipts**; controller signatures and elapsed time are insufficient (a
     rotation to `new_toad = 0` is receipt-free and visibly exits the witnessed guarantee);
   - an **unreceipted local KEL fork** has **no accepted authority** under this trust model;
   - **conflicting threshold-receipted events** are **duplicity evidence** → immediate
     freeze; permanent conviction additionally requires controller-threshold signatures on
     the conflicting establishment event and is restricted to an irreconcilable conflict
     under V1's supported independent-AID rules. Controller signatures without witness
     receipts, or receipts without controller-threshold signatures, cannot convict;
   - **native-KERI state vs Cardano-facing seal/checkpoint mismatch** is **semantic
     correspondence fraud**, handled by the permissionless proof/freeze path;
   - **KERI-ahead / Cardano-behind** is **synchronization lag, not a second valid identity
     branch** — but it is a **real safety window** for Cardano-only consumers.
7. **Consumer contract (honest).** Every future protected action must reference the
   **current unspent per-AID checkpoint** and meet its **current weighted threshold**;
   historical credentials still use KEL/TEL admission evidence. A Cardano transaction
   **cannot know about an unseen off-chain KERI event**. High-security protocols therefore
   **fail closed** once a later witnessed event, an active freeze, or a valid
   mismatch/duplicity proof is presented, and **must publish an anchoring-freshness
   policy/SLA** rather than pretending replay protection alone supplies revocation
   freshness. **#92 does not invent one universal numeric timeout.**
8. **Generic asset-indexer boundary intact.** Locator/freshness availability is for
   **liveness only, never identity truth**; the superwatcher is **not** turned into an
   **authoritative resolver**.

## Background — what is already fixed vs what this ticket opens

The genesis/registration package (#91) and the two evidence gates it rests on
(#97/#98, #99/#100) are **fixed inputs**, not questions reopened here. This
ticket sits strictly downstream of them.

### Fixed logical decisions (do NOT reopen — canonical contradiction → escalate)

1. **#91 §7c decision 2 — MPFS-with-oracle (logical registration/unicity).** The
   oracle consolidates **unicity** (at-most-once absence proof), the **semantic-
   projection attestation** (all tiers), and the **>1-chunk byte-binding
   attestation** in one write. The ≤1-chunk byte binding self-certifies on-chain
   (#97) but does **not** remove the oracle. This is the **logical** registration
   decision; identity-model.md §7c records it explicitly as an **input to #92's
   storage-shape choice, not a reversal**.
2. **#91 §7c decision 1 — oracle-gated registration / permissionless challenge.**
   Activation needs the oracle's projection attestation; a bonded challenge →
   mechanical freeze is permissionless; slash/unfreeze is trusted-adjudicated
   (NOTE-004). Residual censorship + single-attester liveness, deferred k-of-n
   SPO-watcher escape.
3. **#97/#98 — measured BLAKE3 evidence.** A ≤1024-byte inception's byte binding
   `blake3(icp) == cesr_aid` is verified across an **8-block Step + 8-block
   Finish** chain (`spikes/97-blake3-multitx/validators/checkpoint.ak`). Full
   spend-context worst case Step **70.11 % mem / 73.54 % CPU**, Finish 68.44 % /
   72.64 % of the mainnet 14 M / 10 G per-tx budget. Two honesty caveats travel
   with it: the figure **excludes** the ledger→script `Data` deserialization of
   the ~1024-byte redeemer (a **lower bound**), and the spike **does not**
   implement the intermediate-chaining-value lifecycle (see §Step/Finish below).
4. **#99/#100 — cage/thread-token security.** `mpfCage`
   (`onchain/validators/cage.ak`) proves the thread-token/predecessor/version-
   continuity, output-confinement, owner-authorized-against-authenticated-AID, and
   exact burn/lifecycle invariants. **#99 `Modify N ≈ 2` (mainnet, conservative
   declared budgets) is a post-genesis *value-write* mutation bound — NOT a
   genesis or checkpoint-advance batch bound** (NOTE-013). The #99 REPORT's ≈59
   depth-0 handler ceiling is an **estimate**, not a proven cap, and is a
   value-write measurement, not a checkpoint-advance one.
5. **#91 §7c / system-architecture.md §3 — R-KEL classification.** Identity R-KEL
   is the **on-chain cryptographic checkpoint over settled R-ID**, advanced by
   witnessed anchoring seals — **not** a watcher-attested / proof-builder-anchored
   mirror (that family is R-TEL/R-ACDC/R-MAP). **#92 chooses the physical
   checkpoint layout; it must not undo that classification or conflate R-KEL with
   the credential/external mirror plane.**

### The open question (this ticket = open thread 8)

`identity-model.md` §10 thread 8 states the open axis verbatim: **"per-`cesr_aid`
checkpoint UTxO (ordered, no global contention) vs an MPFS checkpoint trie
(aggregate root, batched writes)."** §7c consequences confirm "the
trie-vs-per-AID-UTxO storage shape stays #92's call." The current #24 design
(single registry UTxO + MPF identity trie + depth-10 sliding root window,
`specs/24-keystate/spec.md`) is **evidence/legacy of one candidate (B)**, not
automatically the answer — its own **A12 registry-contention griefing** is
flagged-not-solved (Q4).

## The logical/physical distinction (explicit, load-bearing)

The single most important thing this record fixes is that **registration unicity
is a logical property that a physical layout must *carry*, not *become*.**

| Concern | Decision | Where fixed | Reopened by #92? |
|---|---|---|---|
| Registration unicity ("registered at most once") | **MPFS-with-oracle absence proof** | #91 §7c decision 2 | **No** — logical, fixed |
| Registration gating / challenge | oracle-gated / permissionless challenge | #91 §7c decision 1 | **No** — logical, fixed |
| Projection attestation & teeth | attested + bonded state machine | #91 §7c | **No** — logical, fixed |
| **Physical R-KEL *advance* storage shape** | **sovereign per-AID UTxO (Candidate A)** — operator-ratified (§Operator decision, NOTE-021) | **#92 (this ticket)** | **Decided (A)** |
| Where the AID-owned checkpoint physically lives / is located | its own uniquely-tokenized `(checkpoint_policy_id, aid_asset_name)` UTxO (A) | #92 | **Decided (A)** |
| How advances contend, batch, and grow state | per-AID: no unrelated-AID contention (A); costs sized downstream | #92 | **Decided (A); sizing downstream** |

A per-AID UTxO advance store **does not remove the logical MPFS registration
gate**: unicity remains an MPFS absence proof at registration (decision 2); the
per-AID UTxO would only be the *advance*-path storage that a registered leaf is
promoted into. A singleton-MPFS advance store already *is* the registration trie.
A sharded store partitions the registration trie. **This record keeps all three
compatible with the fixed logical decisions and lets evidence choose the
physical shape.**

## Candidates (A selected on the sovereignty invariant; B/C rejected, kept for the record)

The operator has selected **Candidate A** (§Operator decision, NOTE-021). All three
candidate write-ups are retained for the record — A as the **selected** sovereign
shape, B and C as the **rejected** alternatives whose sovereign residual risks are
documented. The per-candidate cost/throughput notes below are **descriptive
characterization** (and, for A, **implementation-sizing** input), **not** the
selection mechanism — selection is the operator-ratified sovereignty invariant.

Notation: the advancing per-AID checkpoint holds (identity-model.md §6)
`Checkpoint { keys, threshold, next_digest, witnesses, toad, seq }` (and the §7b
`native_sn` binding) — the conceptual key-state, carried on-chain as the inline
**`CheckpointDatum`** (Candidate A); #68 freezes its exact CBOR/wire layout. "Advance" = a witnessed-seal rotation (§4/§6a incoming-set
validation) or a genesis promotion. Reads are **CIP-31 reference-input**,
bring-your-own-proof (§2), so the contended surface is the **write path**
(registration, rare rotation/checkpoint advance, close/freeze), not ordinary
reads.

### Candidate A — per-`cesr_aid` **minted steady checkpoint asset** (AID-bound locator token)

- **What is minted / asset id.** Each registered AID owns a standalone **steady
  checkpoint UTxO** carrying a **quantity-one steady checkpoint locator/state token
  for the registered AID** (a **state token**, **not** the KERI AID itself) plus
  `CheckpointDatum` as inline datum. The token's full Cardano asset id is
  **`(checkpoint_policy_id, aid_asset_name)`**, where **`aid_asset_name` is a
  canonical, domain-separated, collision-resistant, exactly-32-byte derivation of
  the project's canonical qualified AID**:
  `aid_asset_name := blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖ canonical_qualified_aid_bytes)`,
  computed with Cardano's **native `blake2b_256` Plutus builtin** — **not** BLAKE3.
  BLAKE3 is the **expensive, multi-tx checkpointed** computation #97/#98 measure for
  the `blake3(icp) == cesr_aid` **genesis byte-binding** (§Background 3); recomputing
  it here would be both **unnecessary and wrong** for a cheap on-chain *locator label*,
  which only needs a collision-resistant 32-byte name a validator can derive **within
  budget** using a primitive the ledger already provides. The preimage
  `canonical_qualified_aid_bytes` is **#91's canonical qualified CESR AID** — its
  **CESR derivation code** + the **complete 32-byte** `cesr_aid` digest
  (identity-model.md §7 signed-registration package / #97 FR3, "the complete 32-byte
  AID digest, no truncation"). Carrying the derivation code in the preimage
  **preserves the CESR derivation-code/domain distinction** (two AIDs differing only
  in derivation code map to **distinct** asset names) and **invents no second identity
  encoding** — `aid_asset_name` is a deterministic **label of** #91's AID, **not** a
  competing AID, **not** a second self-certification, and **not** a re-computation or
  replacement of the already-established `blake3(icp) == cesr_aid` genesis bind. The
  **only** residual is the exact domain-tag constant + the canonical preimage
  byte-encoding, which **#68 pins** in its CESR-serialization freeze (already #68's
  job); the derivation **shape** (native `blake2b_256` over the domain tag ‖ the
  qualified AID, 32-byte output) is pinned here (NOTE-019).
- **Minted once, after the gate — never from the attempt input.** The steady token
  is **not** minted from the consumed inception `OutputReference` (an
  output-ref-derived token would permit **concurrent duplicate inception attempts**
  and, being derived from a spent input rather than from the AID, would **not** be
  AID-discoverable), is **not** the per-attempt transient cage token, and is **not**
  minted before Finish. It is minted **exactly once, quantity `+1`, only after**
  successful Step/Finish byte binding **AND** the #91 oracle/projection gate **AND**
  the logical MPFS absence/unicity proof — that gate, not the mint timing, enforces
  **at most one** steady checkpoint token per AID. The activation/promotion mint
  transaction places **exactly one** `(checkpoint_policy_id, aid_asset_name)` token
  in **exactly one** checkpoint state output and **rejects any extra asset name or
  quantity under the policy** (single-name, quantity-one mint — the #99 single-`Pair`
  mint check).
- **Combined script; policy id = script hash (#99 pattern) — what the equality does
  and does *not* buy.** Following the #99 combined mint+spend `mpfCage` pattern
  (`targetScriptHash == policyId`, `onchain/validators/cage.ak`), the **applied
  checkpoint validator's script hash is BOTH the payment script hash of the checkpoint
  state output AND the steady token policy id `checkpoint_policy_id`**. This equality
  **names and binds the combined script** — one script is at once the mint policy and
  the spend validator, so the policy/address relationship is never left implicit — but
  the equality **alone does NOT** make the Cardano native asset non-transferable, nor
  does it by itself force the token to live at that address. A Cardano native asset is
  freely transferable at the ledger level; what actually **cages** the token is the
  script's **mint-placement + spend-continuation logic**, an **inductive** invariant:
  1. the **activation mint** executes the combined script's **mint branch** and
     requires exactly **`+1`** of the AID-derived asset in **exactly one** designated
     checkpoint script output (single-name, quantity-one mint — the #99 single-`Pair`
     mint check);
  2. **every normal spend** executes the **spend branch** and requires **exactly one
     successor** at the **same** designated checkpoint script address carrying the
     **same** asset at **quantity one** (the `delta = 0` rotation below);
  3. **only** the separately specified **migration** and **close** branches may move
     the asset to an **accepted successor policy/address** (#99 `Migrating`) or **burn
     `-1`** (#99 `validateEnd`).

  Because the mint places the asset at the designated address, every spend keeps it
  there, and no other branch releases it, the token is confined by **induction over
  its own mint/spend history**, not by the hash equality per se. If a future variant
  needs **separate** mint/spend scripts, **both** hashes and the explicit
  mint-policy-to-spend-validator bind are named; this record does not leave that
  relationship implicit.
- **Discovery is a generic asset lookup, not a bespoke QVI database.** Because the
  token is minted from a **known policy** with an asset name **deterministically
  derived from the AID**, locating an AID's current checkpoint UTxO from the AID
  alone is a **generic multi-asset `(policy_id, asset_name) → current unspent
  output` lookup** answerable by **any** generic Cardano asset index — **not** a
  bespoke, authoritative, QVI-owned `AID → UTxO` database (the earlier "requires an
  off-chain AID→UTxO index" framing is **withdrawn**, NOTE-019; the falsifiable
  discovery criterion is **C9**, §5). Global unicity is **not** provided by the token
  alone — it stays the #91 MPFS registration gate; the steady token is the promoted
  advance **locator**. Given the UTxO, a reader references it **directly** as a
  **CIP-31 reference input** and reads the datum — **proof-simple, no MPF inclusion
  proof** (the token-per-AID read shape, system-architecture.md §6).
- **What downstream computation disappears (inductive trust).** A consumer that reads
  an AID's current checkpoint does **far less** work than replaying KERI:
  - the checkpoint UTxO is supplied as a **CIP-31 reference input** — **read, not
    spent** — so Cardano **does not execute the checkpoint spending validator** during
    the consumer's transaction;
  - the consumer does **not** replay KERI history, **does not** re-verify prior
    rotations or witness-set changes, **does not** recompute the genesis BLAKE3
    `blake3(icp) == cesr_aid`, and (for Candidate A) **supplies no MPF inclusion
    proof** — those transition facts are **inherited inductively** from the genuine
    singleton token's own mint/spend history (each advance already proved its step at
    the time it was written);
  - the consumer performs only a **bounded provenance/state boundary check**: exact
    `(policy_id, asset_name)`, quantity one, an **accepted checkpoint script/version**
    (payment credential + policy-version lineage), a **well-formed inline
    `CheckpointDatum`** with the expected **AID/sequence binding**, and the
    active/freeze/lineage rules relevant to the protocol;
  - **application-specific facts created later remain application work**, and they
    split into two distinct planes that must not be conflated:
    - **A new dApp payload/action** is authorized **under the authenticated *current*
      keys** the checkpoint datum carries — the current weighted threshold over a
      fully bound action. **The checkpoint cannot pre-prove a future payload.**
    - **Historical ACDC issuance / TEL status verification stays historical** and is
      **not** re-checked under current keys: an ACDC is not normally directly signed —
      its **issuance/TEL state event was sealed into the issuer's KEL at that
      historical key state** and remains verifiable through later rotations
      (§ACDC boundary correction). The current checkpoint answers *who authorizes for
      this AID now*; the ACDC issuance-seal / R-TEL evidence answers *was it issued
      then and unrevoked now*. Plus schema and business rules.

  So the consumer **may trust the authenticated current key state** the datum carries
  **after** the bounded boundary check succeeds — and uses it to authorize **new**
  actions, never to re-derive historical credential issuance; it **must not** trust an
  arbitrary datum **merely because** someone sent it to the same script address (a
  stray output at that address, lacking the singleton asset and AID/sequence binding,
  fails the boundary check).
- **State-output shape and the address/datum distinction.** The conceptual
  continuing output is:

  ```text
  CheckpointStateOutput {
    address = ScriptCredential(checkpoint_validator_hash)
              + the designated staking-credential/policy, if any
    value   = min-ADA + exactly 1 (checkpoint_policy_id, aid_asset_name)
    datum   = Inline(CheckpointDatum)
  }
  ```

  The user's "datum needs a scripthash address" point, made precise: **a datum does
  not itself own an address.** The **TxOut carrying the inline `CheckpointDatum`** is
  locked at the designated **script-hash address**
  `ScriptCredential(checkpoint_validator_hash)`. Repeating the script hash **inside**
  the datum is **unnecessary** unless a version/migration invariant requires it; if
  retained, this record must state why and cross-check it against the address. Normal
  transitions require the **exact designated continuing-output address**, not merely
  "some script address."
- **Where the current key lives.** The current weighted key state lives in
  **`CheckpointDatum`** — the inline datum of the uniquely tokenized checkpoint UTxO.
  **The token is the stable locator; it does not store the key.** At #92's
  abstraction level `CheckpointDatum` carries the already-canonical conceptual
  checkpoint fields (identity-model.md §6): `keys` (weighted `[(pubkey, weight)…]`),
  weighted `threshold` (KERI `kt`), `next_digest`, `witnesses`, `toad`, `seq`, and
  the §7b `native_sn`/AID binding. **#68 (not #92) freezes the exact CBOR/wire
  layout** of this state later; #92 fixes only the conceptual shape.
- **Token / predecessor / placement / close-burn-migration.** Steady checkpoint
  token per AID (distinct from the **transient per-attempt inception cage token**,
  see below); predecessor/version binding via the #99 `Migration` pattern
  (`predecessorPolicy` validator parameter, attacker-created predecessor cannot
  satisfy migration by construction); exact output placement = the single continuing
  `CheckpointStateOutput` above; close = the #99 `validateEnd` `-1` burn coupling;
  migration = #99 `Migrating`. **#99 cage invariants map directly** (per-AID UTxO is
  structurally the cage shape at population 1-per-AID).
- **Step/Finish confinement.** Confinement uses a **per-attempt transient
  cage/thread token minted for the inception attempt** (not the steady checkpoint
  token), scoping the ≤1-chunk Step/Finish chain so it **confines the intermediate
  chaining value** (`checkpoint.ak` `Datum.cv`) — supplying exactly the
  thread-token confinement the spike's `has_continuing_output` (address+value
  only, **no token**) omits. Because the token is minted **per attempt**,
  concurrent inception attempts (including duplicates racing for the same eventual
  AID) each get a **distinct** transient token/UTxO and **cannot** consume one
  another's intermediate state. **Only after Finish + the #91 oracle gate + the
  MPFS absence/unicity proof** is the unique steady per-AID checkpoint token minted
  (or the transient token promoted) — that gate, not the mint timing, enforces
  at-most-one steady checkpoint per AID.
- **Normal rotation transition (state machine; `delta = 0`).** A normal rotation
  (i) **consumes** the current checkpoint UTxO identified by the steady asset;
  (ii) **authenticates** the existing datum's current weighted key/witness state and
  the witnessed **incoming-set rotation** (§6a, fixed upstream); (iii) requires
  **`new.seq = old.seq + 1`**, the correct old→new key/`threshold`, witness/`toad`,
  `next_digest`, and `native_sn` transition, with the **AID and `aid_asset_name`
  invariant unchanged**; and (iv) **creates exactly one** continuing checkpoint
  output at the **same** designated checkpoint script address, carrying **the same
  asset id at quantity one** and the **new** inline `CheckpointDatum`. Normal
  rotation has **no mint or burn** for the steady asset (**`delta = 0`**): the token
  **moves** from the consumed state output to its **unique successor**. It **rejects**
  zero successors, multiple successors, token duplication, token leakage to a
  **different** address, `aid_asset_name` changes, AID changes, and sequence skips.
  **Therefore an exact asset index automatically resolves the new `txid#index` after
  rotation** — Alice does **not** update a QVI-owned directory.
- **Rotation vs migration vs close (kept separate).** **Script migration** is
  **separate** from normal rotation: it consumes the predecessor state and, under #99
  predecessor/successor binding, **atomically** moves to the explicitly allowed
  successor script/policy — a generic resolver follows the **accepted policy-version
  lineage** (§5). **Close/end** stays the **owner-authorized exact `-1` burn** (#99
  `validateEnd`) and must carry an **unambiguous closed/tombstone discovery story**
  via the logical registration record or committed history (a burned token yields no
  live UTxO, so discovery must not read "closed" as "never registered").
- **Serialization / stale / batch / replay.** Rotations serialize on
  **that AID's own UTxO only** — no global contention. A witness-set change (§6a)
  is validated against the incoming (new) set — no outgoing endorsement — and advanced once. Stale-root
  window largely **dissolves** (the datum *is* the tip; freshness = "spend the
  tip"), reducing the #24 A11 depth-10 stale-proof surface. **Batching is not
  required for parallelism** (each AID advances on its own UTxO), but A **can
  optionally batch** multiple independent per-AID inputs into one tx (e.g. a single
  operator advancing several AIDs it controls) — one advance per AID within the
  batch, bounded by the whole-tx budget. Replay/misbinding rejected by `seq`
  monotonicity + domain-bound message (as #24 `rot_msg`).
- **Griefing / emergency latency.** No shared-UTxO race; but **permissionless
  inception spawns one global UTxO per AID → global UTxO-set / min-ADA bloat**
  griefing, mitigated by the `bond_reg` inception deposit (#91 teeth), not by
  contention limits. Emergency rotation runs on the AID's own UTxO → **lowest
  latency**. Freeze stays a **separate** registry path (R-FRZ), independent of the
  advance UTxO.
- **Costs.** Throughput: fully parallel (no contention). State growth: **O(#active
  AIDs) UTxOs, each locking min-ADA while the AID is active** — reclaimable on a
  valid close/burn via the #99 `validateEnd` coupling, **not** locked forever — the
  dominant cost. Proof size: minimal (direct datum read via CIP-31 reference input).
  Off-chain: no batch coordination required; discovery is a **generic multi-asset
  `(policy_id, asset_name)` index** (any indexer/node/sidecar/replica — §5, C9), an
  operational availability/privacy concern shared with other chain-data providers,
  **not** a bespoke authoritative `AID → UTxO` directory (NOTE-019).

### Candidate B — singleton MPFS checkpoint/root UTxO (current #24 design)

- **Location / uniqueness.** One MPFS UTxO holds `identity_root`; leaves =
  `cesr_aid → commit(Checkpoint)`. B **intentionally co-locates** the logical
  registration trie and the physical advance state in one root — a **candidate
  design choice**, **not** forced by #91: the #91 logical MPFS registration gate is
  distinct from B's decision to *also* store advance state in the same trie. **Only
  A** keeps registration a separate logical gate while placing advance state
  elsewhere (registration-gate → per-AID promotion); **C, like B, co-locates**
  registration and advance in one trie, but **sharded** across K deterministic lanes
  (C's own candidate choice — see Candidate C). **None of the three is forced by
  #91.** **Global unicity native** (absence proof against the single root, #24
  Inception check 3).
  AID-owned checkpoint located by **MPF inclusion proof** `cesr_aid →
  commit(key_state)` against a root in the depth-10 window (§2, #24
  `RegistryDatum.root_window`).
- **Token / predecessor / placement / close-burn-migration.** **Single** registry
  thread token minted once at registry genesis (#24 "Registry UTxO"); predecessor/
  version binding at the registry level. Close/burn is a leaf-tombstone
  (`Closed`/`FrozenFatal`), not a token burn. #99 invariants apply to the single
  registry UTxO, not per AID.
- **Step/Finish confinement.** The singleton root is **not** itself a natural home
  for a genesis chaining value; confinement needs a **separate transient
  per-inception cage UTxO** (the #97 checkpoint UTxO) with its **own thread
  token** so concurrent unrelated inceptions do not collide/consume each other on
  the singleton. This transient confinement is **orthogonal** to B's steady state
  but is a **required, unbuilt invariant** (identity-model.md §7c: "MUST confine …
  a required #24/#92 integration invariant").
- **Rotation / serialization / stale / batch / replay.** **All AIDs serialize on
  the single registry UTxO** — this is #24 **A12 registry contention** (Q4
  flagged-not-solved). Batched writes (a `Modify`-style fold) amortize; the
  **depth-10 sliding root window** lets cages accept proofs against recent roots
  (#24 A11 stale-proof floor) and enables the MPFS **snapshot-and-rebuild**
  submission pattern (`docs/architecture/amaru-integration.md`). Batch atomicity:
  one advance can fail the shared tx; replay/misbinding via `seq` + domain
  binding.
- **Griefing / emergency latency.** A12: an attacker races honest rotations by
  spamming valid ops (own-AID rotations are free) → **delay, not forgery**;
  mitigation is snapshot-rebuild + fee/deposit tuning. Emergency rotation **queues
  behind the single-UTxO write cadence** (operational.md ≈ 1 op/block) unless
  batched → **highest emergency-latency risk of the three**. Freeze stays a
  separate R-FRZ registry, so emergency **freeze** need not queue behind checkpoint
  advances even though rotation does.
- **Costs.** Throughput: contention-bound (Q4). State growth: **O(1) UTxO**
  (bounded min-ADA); trie grows but not the UTxO set. Proof size: grows with trie
  depth — **MEASURE against the actual MPF implementation** (asymptotics **not**
  assumed `O(log #AIDs)` unless proven for that MPF). Off-chain: batch/window
  coordination (submission ordering, snapshot rebuild).

### Candidate C — lane-sharded MPFS (concrete hybrid) [+ hot/cold variant]

- **Shape.** **K parallel MPFS root UTxOs (lanes)**, each holding a disjoint shard
  of the identity trie keyed by a deterministic function of the AID —
  `lane = f(cesr_aid)` (e.g. a fixed prefix of `cesr_aid`, K a power of two). Each
  AID's checkpoint lives in exactly one lane; located by computing `lane` then an
  MPF inclusion proof against that lane's root. This trades B's global contention
  for **≈ contention/K** while keeping **batched writes** and a **bounded UTxO
  count (K, not #AIDs)**.
- **Location / uniqueness.** **C is a sharded co-location design:** like B (and
  **unlike** A), the logical MPFS registration/unicity is implemented **in the same
  tries that hold advance state** — here **across K deterministic lanes**, with each
  AID's advance leaf living in its assigned lane. This is **C's candidate choice
  (compatible with #91, not forced by it)**; A instead keeps registration a
  **separate** logical gate → per-AID promotion. Global unicity is a **per-lane
  absence proof** in the lane's identity trie; because `lane` is a **total,
  deterministic** function of `cesr_aid`, an AID has exactly one admissible lane, so
  at-most-once holds across the union of lanes (an AID cannot be inserted in two
  lanes without violating `lane = f(cesr_aid)`). **That same determinism is public
  and permissionless, so `lane` is grindable** — an attacker can search `cesr_aid`
  values until `f(cesr_aid)` lands in a **chosen victim's lane** (see Griefing). Each
  lane carries its own thread token; predecessor/version binding per lane (#99
  pattern), K instances.
- **Step/Finish confinement.** Same transient per-inception cage UTxO as B (own
  thread token); the target lane is fixed by `f(cesr_aid)`, so confinement and
  lane assignment do not interact.
- **Rotation / serialization / stale / batch / replay.** Rotations serialize only
  against the **same lane** → cross-lane advances are parallel. Depth-10 window,
  snapshot-rebuild, batch atomicity, and replay/misbinding behave as B **per
  lane**. Emergency rotation queues only behind same-lane writes.
- **Griefing / emergency latency.** **Average / uncoordinated** contention drops
  by ≈K: independent honest advances spread across K lanes, so a random AID's lane
  sees ≈`1/K` of B's contention and ≈`B/K` emergency latency. **But `lane =
  f(cesr_aid)` is grindable:** a permissionless attacker can generate candidate
  AIDs until `f(cesr_aid)` lands in a **victim's lane**, then spam that lane. So C
  **does not bound targeted worst-case victim-lane contention or emergency latency
  to `B/K`** — under a targeted grinding attack the victim lane degrades toward B's
  single-lane behaviour. Average-case and adversarial/targeted-case are therefore
  **separate criteria** (matrix C2/C4). Mitigations (per-lane deposits/fees, larger
  K, keyed/secret or re-sharded `f`) are **cost-raising, not bounding**, and a fixed
  K must plan for **skew and re-shard migration** (changing K or `f` re-homes every
  AID's lane — a versioned migration, not free).
- **Costs.** Throughput: K-way parallel (average case; a grindable target lane is
  not). State growth: **O(K) UTxOs** (bounded, min-ADA ≪ per-AID). Proof size:
  grows with per-lane trie depth — **MEASURE against the actual MPF implementation**
  (not assumed `O(log(#AIDs/K))` unless proven). Off-chain: K submission lanes +
  lane routing + a re-shard/migration plan for K/`f` changes.
- **Variant (recorded, not the concrete C):** **hot per-AID UTxO + cold MPFS
  tail** — promote frequently-rotating AIDs to a per-AID UTxO (A) while the cold
  majority stays in MPFS (B). Higher off-chain complexity (promotion/demotion
  bookkeeping, dual read shapes) and a non-deterministic hot/cold boundary; the
  **lane-shard is the primary concrete C** because it is deterministic and keeps a
  single read shape.

### Transient inception-cage lifecycle & cleanup (all candidates)

Every candidate confines the ≤1-chunk Step/Finish chain with a **per-attempt
transient cage/thread token** (A's *steady* per-AID checkpoint token is minted only
**after** Finish + oracle gate + MPFS unicity — NOTE-018). Because inception is
**permissionless**, an attacker can **create and abandon many** intermediate cage
UTxOs, so the lifecycle is specified exactly and its state-bloat/cleanup burden is
**measured, not hand-waved**:

- **Mint binding.** The transient token is minted **tied to the consumed attempt
  input** (the inception `OutputReference`), so each attempt yields a **distinct**
  token/UTxO and one input cannot fund two live attempts.
- **Step invariant.** Each Step **preserves exactly one** transient token in
  **exactly one** continuing output (address + value + **token**), carrying the
  intermediate `cv` forward — no fan-out, no duplication.
- **Finish invariant.** Finish **consumes and burns-or-promotes the token exactly
  once**: a valid Finish burns the transient token (its byte binding having gated
  the #91 oracle + MPFS-unicity activation), and for A that Finish is the point
  **after which** the **steady** per-AID checkpoint token is minted/promoted. No
  path both keeps the transient token alive and activates a checkpoint.
- **Failure / abandonment.** An attempt that never Finishes has a **bounded
  timeout → reclaim/burn** path that **cannot activate** the checkpoint and
  **cannot bypass byte binding** — the only exits are (i) a valid Finish or (ii) a
  timed-out reclaim that **burns** the transient token and returns the funding
  deposit. **The timeout value is NOT invented here**: if it affects the decision it
  is a threshold the decision slice **ratifies before measurement** (NOTE-016),
  routing any operator decision through `questions/`.
- **Funding cleanup.** The **bond / min-ADA** locked on the transient UTxO **funds
  its own cleanup** (reclaim/burn), so abandoned attempts are self-financing to
  unwind rather than a permanent min-ADA leak; the griefer pays the deposit per
  attempt.

This transient-cage surface — **peak concurrent live attempts** and
**abandoned-attempt cost** — is a **distinct** state/UTxO-bloat concern from the
steady stores (A's per-AID UTxOs, B/C's tries) and is **measured by the evidence
slice** (matrix C3b, §Evidence), not assumed.

## Characterization matrix — descriptive criteria (NOT the selection mechanism)

> **The selection was made on the sovereignty invariant, not on this matrix**
> (§Operator decision, NOTE-021). This matrix is retained as **descriptive
> characterization** of the three shapes and, for Candidate A, as an **enumeration
> of the implementation-sizing quantities to measure downstream**. It is **not** a
> selection scoreboard: no candidate is chosen or rejected here on a `MEASURE` cell,
> and **B/C measurement is not required** for the decision. The cells below therefore
> stay honest placeholders — the A-sizing figures are measured **downstream** (a
> Candidate-A implementation gate, §Candidate-A implementation-sizing plan), and the
> B/C comparison figures are **deferred/withdrawn** with the rejected candidates.

Each criterion originally carried a **falsifier** (kept for the record of what each
shape's failure mode would have been). Cells marked `MEASURE` are **not filled here**
and are **not** a blocker on the decision. **No values are invented in this record.**

**Any thresholds/measurement discipline below applies only to the downstream
Candidate-A implementation-sizing work** — thresholds ratified with provenance
*before* the A-sizing measurement, never chosen after seeing a result (NOTE-016, now
scoped to A-sizing only). **These thresholds are not a precondition of the sovereign
decision** and do not gate this record; the old evidence-gated B/C selection premise
is superseded by the operator decision (NOTE-021).

| Criterion (falsifier) | A per-AID UTxO | B singleton MPFS | C lane-shard |
|---|---|---|---|
| **C1a Registration-pipeline per-tx budget fit** — each registration tx measured at its **own** boundary: Step(s), Finish, and activation/promotion (oracle gate + MPFS absence/unicity + selected-store materialization, incl. A's post-Finish steady-token mint) each fit mainnet 14 M mem / 10 G CPU. *Falsifier: any single registration tx cannot fit at realistic proof depth.* | MEASURE | MEASURE | MEASURE |
| **C1b Rotation-advance per-tx budget fit** — the *separate* rotation-advance tx (§6a incoming-set threshold Ed25519 + selected physical-storage update at realistic MPF depth + continuing output/token + `Data` boundary) fits mainnet 14 M mem / 10 G CPU at N=1. *Falsifier: cannot fit N=1 at realistic depth. Disjoint transactions are never summed into one per-tx claim.* | MEASURE | MEASURE | MEASURE |
| **C2 Sustained honest advance throughput ≥ ratified SLO** — measured **separately** for the **average/uncoordinated** and the **targeted/adversarial** case (grinding a victim lane in C). *Falsifier: measured advances/block below the ratified SLO and batching cannot reach it within the C1b budget, in whichever case that criterion requires.* | high (parallel) | MEASURE (A12-bound) | MEASURE (average K-way; targeted victim ≈ single-lane) |
| **C3 State/min-ADA growth per 10⁶ active AIDs ≤ ratified capital-lock budget.** *Falsifier: projected locked min-ADA × active population exceeds the ratified budget (A's min-ADA is reclaimable on close/burn — count active, not cumulative).* | MEASURE (O(#active AIDs)) | O(1) UTxO | O(K) UTxO |
| **C3b Transient inception-cage bloat & cleanup ≤ ratified bloat budget** — the shared per-attempt transient cage (all candidates) under permissionless spam: **peak concurrent live attempts** and **abandoned-attempt cost** (min-ADA held + reclaim/burn cost), with the timeout/reclaim path self-funding. *Falsifier: peak concurrent transient UTxOs or unreclaimable abandoned-attempt min-ADA exceeds the ratified bloat budget, or the reclaim/burn path is not deposit-funded.* | MEASURE (transient cage) | MEASURE (transient cage) | MEASURE (transient cage) |
| **C4 Emergency-rotation latency under contention ≤ ratified SLO** — measured for both the **average** lane and a **grinding-targeted victim** lane (C). *Falsifier: cannot settle a preempting rotation within the ratified SLO; for C the targeted-victim latency is **not** assumed `B/K` and must be measured under grinding.* | low | MEASURE (highest) | MEASURE (avg ≈B/K; targeted → toward B) |
| **C5 Step/Finish confinement realizable with zero cross-AID interference** — a **required, unbuilt design** the delegated prototype/harness must demonstrate, not an implemented fact. *Falsifier: concurrent unrelated inceptions can consume one another's intermediate `cv`.* | VERIFY (per-attempt transient token) | VERIFY (transient cage token) | VERIFY (transient cage token) |
| **C6 Per-action read cost (CIP-31 ref + proof size) ≤ ratified cap.** *Falsifier: proof/redeemer size or read exec-units exceed the ratified cap.* | minimal (datum read) | MEASURE (MPF proof size, asymptotics per actual impl) | MEASURE (per-lane MPF proof size, asymptotics per actual impl) |
| **C7 #99 cage invariants preserved** (predecessor/version continuity, output confinement, exact burn/lifecycle) — the integrated candidates are **unbuilt**, so this cannot read "yes" here: the delegated prototype/harness **MUST prove every inherited #99 invariant** at the candidate's stated scope. *Falsifier: any invariant cannot be reproduced.* | PROVE (per-AID cage) | PROVE (registry-scoped) | PROVE (per-lane) |
| **C8 Migration/downstream cost to #68/#24/#25/#44 within ratified re-cut bound & bisect-safe.** *Falsifier: any downstream re-cut exceeds the ratified bound or is not expressible as a versioned, additive change.* | MEASURE | MEASURE | MEASURE |
| **C9 Trust-minimized generic discovery** — an AID's current checkpoint state is located by an **exact `(policy_id, asset_name) → current unspent output` lookup** answerable by **any** generic Cardano asset index (indexer/node/sidecar/replica), and the design **tracks rotation successors**, **follows migration/policy-version lineage**, **rejects stale/forged resolver answers against the ledger** (singleton asset + designated script address + inline datum/AID binding), and gives **closed/tombstone** state an unambiguous discovery story — the resolver supplies availability/freshness, **not** identity truth. *Falsifier: discovery depends on an exclusive/authoritative issuer/QVI database, OR lacks exact-asset lookup, rotation-successor tracking, migration lineage, stale-result rejection, or closed-state semantics.* This is a **design-property proof (no numeric threshold)** — recorded `PASS`/`FAIL` with a real evidence class, **not** `class=proved`. | VERIFY (generic `(checkpoint_policy_id, aid_asset_name)` asset lookup; §5) | VERIFY (MPF inclusion vs windowed root **+ off-chain MPFS state materializer/proof builder**) | VERIFY (per-lane MPF inclusion **+ off-chain MPFS state materializer/proof builder**) |

**Selection rule (applied): the operator-ratified sovereignty invariant.** The
selection is **not** run over this matrix. The operator selected **Candidate A**
because it is the only shape under which each AID's current-authority state advances
through its **own uniquely-tokenized UTxO**, so **unrelated and hostile AIDs cannot
contend with, consume, serialize, or delay** it (§Operator decision). **B is rejected**
because its shared/global checkpoint UTxO serializes unrelated identities; **C is
rejected** because a public/grindable lane lets hostile AIDs target a victim's lane
and makes sovereignty depend on shard machinery. The **C9 trust-minimized-discovery**
property is a **hard requirement A satisfies** (generic `(policy_id, asset_name)`
lookup; no exclusive/authoritative issuer/QVI database). The canonical docs are
updated with this decision. **The A-implementation-sizing measurements and
live-boundary smoke are a downstream implementation gate, retained honestly and never
represented as the selection reason** — a claim that A "won" a measured
throughput/capital/cost contest would misrepresent the sovereign basis and is
forbidden.

## Cross-cutting concern coverage (mapped to brief.md)

- **Uniqueness / authenticity & locating an AID-owned checkpoint.** Unicity stays
  the #91 logical MPFS gate in all candidates; *authenticity of an advance* is the
  §4/§6a witnessed-seal + validator check (no watcher trust added, §3). Location
  (falsifiable as **C9**, §5): A = an **exact `(checkpoint_policy_id, aid_asset_name)`
  asset lookup** via any generic Cardano index, then a direct CIP-31 reference-input
  datum read; B = MPF inclusion vs windowed root (**+ off-chain MPFS state
  materializer/proof builder**); C = `f(cesr_aid)` lane then MPF inclusion (**+
  off-chain MPFS state materializer/proof builder**). A resolver supplies
  availability/freshness, **not** identity truth — a stale answer yields retry/failure,
  re-checked against the ledger (singleton asset, script address, datum/AID binding,
  policy lineage), never forged authority.
- **Token/policy-token shape, predecessor/version binding, exact output
  placement, close/burn/migration, #99 interaction.** Per candidate above; all
  reuse the #99 `Mint`/`Migration`/`Burning` + `predecessorPolicy` pattern and the
  `validateEnd` burn coupling. #99 invariants are a **hard preservation
  requirement** (guard rail), not re-litigated.
- **Registration Step/Finish intermediate confinement & cross-AID interference.**
  The spike `checkpoint.ak` `has_continuing_output` preserves address+value but
  **carries no thread token**, so the intermediate `cv` is **unconfined in the
  spike** — the required, unbuilt #24/#92 invariant. **Every candidate must confine
  it via a per-attempt transient cage/thread token, A included** — A's *steady*
  checkpoint token is minted only after Finish + oracle gate + MPFS unicity, so
  during Step/Finish A too relies on the transient per-attempt token — such that
  concurrent unrelated AIDs **cannot** interfere with or consume one another's
  intermediate state (C5, NOTE-018).
- **Rotation ordering, same-AID serialization, witnessed incoming-set rotation, stale
  proofs, snapshot/rebuild, batch atomicity, replay/misbinding.** Same-AID
  serialization: A per-UTxO, B global, C per-lane. Witness-set change (§6a): receipts
  validated against the incoming `(new_witnesses,new_toad)` set, no outgoing
  endorsement, one advance. Stale proofs/window + snapshot-rebuild: dissolve in A, depth-10 window
  in B/C. Batch atomicity + replay: `seq` monotonicity + domain-bound message in
  all; batching only in B/C.
- **Permissionless-inception / global-UTxO griefing & emergency-rotation
  latency; separate freeze path; freshness ≠ replay.** A: global UTxO bloat
  (deposit-mitigated), lowest latency. B: A12 shared-UTxO delay, highest latency.
  C: **average-case** lane-confined spam at ≈B/K, but **`lane = f(cesr_aid)` is
  grindable** — a targeted attacker can land AIDs in a victim's lane, so C's
  **targeted worst-case** contention/latency is **not** bounded to B/K and degrades
  toward B (average-vs-adversarial are separate matrix criteria C2/C4, NOTE-017).
  The **freeze path is a separate R-FRZ registry** in every candidate and stays
  visible. **Replay protection alone does NOT provide revocation freshness** —
  freshness is the §9 staleness/liveness knob (submission incentive + freeze
  fast-path), orthogonal to replay rejection; this record does not conflate them.
- **Write throughput/contention, state/output growth & min-ADA, datum/redeemer &
  proof sizes, MPFS proof/update work, batching bounds, off-chain coordination.**
  Enumerated per candidate (§Candidates) and rowed in the matrix (C2/C3/C6). The
  **batching bound is candidate-specific and MUST be measured for the checkpoint-
  advance path** — it is **not** the #99 `Modify N ≈ 2` value-write bound
  (NOTE-013).
- **Migration & downstream (#68 / #24 / #25 / #44).** #68 wire schema: the chosen
  shape fixes whether the checkpoint is a **leaf value** (B/C) or a **UTxO datum**
  (A), which #68 must pin (with Haskell/Aiken golden parity) — recorded as a
  consequence, not decided/absorbed here. #24 validator/redeemer: the registry
  validator + redeemer differ (single vs per-AID vs per-lane spend); A collapses
  the depth-10 window, B/C keep it. #25 replay/proof construction: A is
  proof-simple (no MPF proof), B/C carry MPF inclusion proofs of candidate-
  specific depth. #44 live-devnet proof: the selected shape must land a live
  checkpoint-advance smoke (§Evidence). **Consequences documented, not solved.**
- **Honesty boundaries, residual risks, unsupported capabilities, remaining
  work.** §Honesty below.
- **Live-boundary-smoke limitation.** §Evidence below.

## Candidate-A implementation-sizing & live-boundary measurement plan (downstream; not selection evidence)

> **These measurements are Candidate-A implementation sizing and live-boundary
> honesty, a downstream implementation gate — not the reason A was chosen and not a
> precondition of this decision** (§Operator decision, NOTE-021). No value here is
> invented, fabricated, or back-filled, and none is presented as the selection basis.
> The **B/C comparison** measurements are **deferred/withdrawn** with the rejected
> candidates; what survives is the sizing of the **selected** shape (A) plus the honest
> characterization already stated. The prototype/harness/measurement that produces
> these figures is **behavior-changing** and belongs to a downstream implementation
> ticket, **not** authored in this design record.

### What exists (provenance + honesty caveats)

- **#97 checkpoint core** (`spikes/97-blake3-multitx/**`, REPORT): Step 70.11 %
  mem / 73.54 % CPU, Finish 68.44 % / 72.64 %, **≤1-chunk core/handler only** —
  **excludes** the #99 state/thread lifecycle and the ledger `Data` boundary; a
  **lower bound**, not a checkpoint-advance cost.
- **#99 cage** (`onchain/validators/cage_measurements.ak`, REPORT): Mint/Migrate/
  End < 1 %; `Modify(n) ≈ 225,990 + 209,332·n` mem / `73,072,528 + 122,370,488·n`
  CPU (depth-0, handler-only); `fromData` adds ≈ +21,924 mem / +6,376,988 CPU per
  request; ≈59 depth-0 **estimated** memory crossing; live `withDevnet` sweep
  supported **N=2 mainnet** at *conservative declared* budgets. **All of this is a
  value-write measurement; none of it is a checkpoint-advance or genesis batch
  bound** (NOTE-013).

### What must be sized downstream for Candidate A (not a decision precondition)

**This is the downstream Candidate-A implementation-sizing scope** — it does **not**
gate the sovereign decision (NOTE-021). If that downstream work adopts SLO/cap
thresholds, they are ratified **with provenance before** the A-sizing measurement,
never chosen after seeing a result (NOTE-016, rescoped to A-sizing). The **B/C**
figures below are retained only as historical characterization of the rejected shapes;
the required sizing is **Candidate A's**.

For **Candidate A** (and, where noted, historical B/C characterization), produce
measured figures at the **actual transaction boundary of each distinct transaction**,
not a primitive in isolation and **never by summing disjoint transactions into one
per-tx claim**:

1. **Registration pipeline** — measure each of its transactions at its **own**
   boundary: the ≤1-chunk **Step(s)**, **Finish**, and **activation/promotion**
   (oracle gate + MPFS absence/unicity + selected-store materialization, incl. A's
   post-Finish steady-token mint/promotion). Each uses the **per-attempt transient
   cage/thread token** for confinement. Report per-tx ex-units/size (C1a).
2. **Rotation advance** — a **separate** tx exercising the §6a **incoming-set threshold
   Ed25519** verification, the **selected physical-storage update** (MPF update at a
   stated, **non-zero** proof depth for B/C; direct datum spend for A), the
   continuing output/token placement, and the ledger `Data` boundary
   (compiled-validator eval, #99 S8 method). Report per-tx ex-units/size (C1b).
3. Report **end-to-end latency/fees** across the registration pipeline and across a
   rotation **separately**; **do not** collapse the multi-tx inception path and the
   rotation path into a single per-tx budget figure.
4. A **batching sweep** for B/C to find the **checkpoint-advance** batch bound
   (distinct from #99's value-write bound), reporting the binding constraint
   (memory / CPU / tx-size) and its provenance; also measure A's **optional**
   multi-AID batch (not required for parallelism).
5. **State/min-ADA projections** for A/C from the measured per-UTxO datum + token
   min-ADA × projected **active** population (A's min-ADA reclaimable on close/burn).
6. **Transient inception-cage load** (all candidates, matrix C3b): the per-attempt
   transient cage/thread token's **mint/Step/Finish/timeout-reclaim** ex-units/size,
   the **peak concurrent live attempts** and **abandoned-attempt cost** (min-ADA held
   + reclaim/burn) under permissionless spam, and confirmation the reclaim/burn path
   is **deposit-funded** and **cannot activate or bypass byte binding**. The timeout
   value is a **ratified-before-measurement** threshold if it affects the decision
   (NOTE-016) — **not** invented in measurement.
7. **Discovery model (C9, per candidate; design-property proof, no numeric
   threshold).** Verify and record (`PASS`/`FAIL`, class derived/declared) that
   discovery is: for **A** an **exact `(checkpoint_policy_id, aid_asset_name)` lookup**
   answerable by any generic Cardano asset index (indexer/node/sidecar/replica); for
   **B/C** an MPF inclusion proof against a windowed root **plus an off-chain MPFS
   state materializer/proof builder** (an on-chain root is **not** free leaf
   discovery). For every candidate confirm it **tracks rotation successors**,
   **follows migration/policy-version lineage**, **rejects stale/forged resolver
   answers against the ledger** (singleton asset + designated script address + inline
   datum/AID binding), and gives **closed/tombstone** state an unambiguous discovery
   story. A candidate whose discovery **depends on an exclusive/authoritative
   issuer/QVI database** (or lacks any of the above) **fails C9**.

The measurement harness, fixtures, and any prototype validators are **behavior-
changing** and are **dispatched to the driver+navigator pair** — this record does
not author them.

### Live-boundary smoke (and its stated limitation)

Once a candidate is provisionally selected, land a **named live-boundary smoke**
on the operator's tx-tool devnet (`withDevnet`, in the `nix run .#e2e-sweep` /
`KERI_CAGE_SWEEP` family, reusing `Cardano.KERI.AID.E2E.MpfProof.prove` for real
depth-N proofs) that **submits a real checkpoint-advance tx and asserts the node's
Phase-1/Phase-2 outcome** — failing loudly at the node boundary. **Stated
limitation (do not overclaim):** the observed devnet `maxTxExUnits` is **140 M
mem / 10 G CPU** (memory 10× mainnet, CPU identical) and client `evalTxExUnits`
**hung** on the cage script in #99, so the smoke proves **boundary correctness**
and a **conservative** bound, **not** a precise mainnet ex-unit fit. A unit/golden
proof of a candidate validator **does not** substitute for this live node
boundary; the precise mainnet ex-unit fit remains an Aiken/`uplc eval`
measurement (C1), and the smoke is its live corroboration, not its replacement.

## Honesty boundaries & residual risks

- **Candidate A is selected by the operator-ratified sovereignty invariant; B and C
  are rejected.** The selection is a normative security/product decision (§Operator
  decision, NOTE-021), **not** a measured throughput/capital/cost-matrix win, and it
  does **not** wait on ratifying B/C thresholds. **B/C comparison measurement is
  deferred/withdrawn honestly.** The Candidate-A cost/tx-size/min-ADA/fan-in figures
  and the live-boundary smoke are a **downstream implementation-sizing gate**, retained
  honestly and **never** represented as the reason A was chosen; presenting a
  fabricated/back-filled measurement as the selection basis is forbidden. The earlier
  "no candidate is selected / matrix open pending evidence" premise is **superseded**
  (NOTE-021).
- **The advance path is unbuilt and unmeasured, and its transactions are
  distinct.** The registration pipeline (Step/Finish confinement → Finish → oracle +
  MPFS unicity + store materialization) and the **separate** rotation-advance tx
  (incoming-set threshold verify + MPF update) have never been built or measured; #97 and #99 measure
  disjoint fragments. **Genesis Step/Finish and the rotation advance are different
  transactions on different paths and must never be summed into one per-tx budget
  claim** (NOTE-018). "The intermediate value is confined" is a **required #24/#92
  invariant**, phrased as such, not an implemented fact.
- **Candidate A discovery uses a generic asset index, not a bespoke QVI DB.** A's
  steady checkpoint token is minted from a **known policy** with an **AID-derived
  asset name**, so discovery is a **generic multi-asset `(policy_id, asset_name) →
  current unspent output` lookup** answerable by any generic Cardano index — **not**
  the bespoke/authoritative QVI-owned `AID → UTxO` database earlier drafts implied
  (**withdrawn**, NOTE-019). The index supplies **availability/freshness, not
  identity truth** (a stale answer is re-checked against the ledger → retry/failure,
  not forged authority; C9). The steady token is minted **only after** Finish + the
  #91 oracle gate + MPFS unicity — **not** from an inception `OutputReference` before
  Step/Finish (which would permit concurrent duplicate attempts). During Step/Finish
  every candidate, A included, confines the intermediate `cv` with a **per-attempt
  transient** cage/thread token (NOTE-018). **B/C are held to the same honesty:**
  their on-chain root still needs an off-chain MPFS state materializer/proof builder —
  root presence is **not** free leaf discovery.
- **#99 Modify N ≈ 2 is not this ticket's batch bound** (NOTE-013).
- **Griefing is mitigated, not eliminated.** A's UTxO-bloat, B's A12 shared-UTxO
  delay, and the **transient inception-cage create/abandon** surface (all candidates)
  are bounded by deposits/fees/sharding/timeout-reclaim, not removed; a capitalised
  griefer can still force cost, and peak-concurrent/abandoned-attempt load is
  **measured, not assumed** (C3b).
- **Freshness is a separate liveness knob.** Replay/misbinding rejection is not
  revocation freshness (§9); the freeze fast-path + submission incentive own that,
  on a separate R-FRZ path.
- **R-KEL classification is preserved, not revisited.** This record picks a
  physical layout only; it keeps R-KEL an on-chain checkpoint over settled R-ID,
  outside the watcher-mirror / root-consensus / slashing plane (§3/§5/§11).
- **Prototype framing.** No generic KERI/TEL/ACDC interop or production-readiness
  claim; the merged evidence is #97/#98 and #99/#100.

## Clarifications

### 2026-07-11 — NOTE-013 (checkpoint-advance batch bound ≠ #99 value-write bound)
The #99 `Modify N ≈ 2` (mainnet) / `N ≈ 4` (devnet) figures — and the ≈59 depth-0
handler-ceiling **estimate** — are **value-write** measurements at conservative
declared budgets. The checkpoint-advance work spans **two distinct transaction
families, each unmeasured and each heavier per item than the #99 value-write**, and
they are **never summed** into one per-tx claim (NOTE-018): (i) the **registration
pipeline** — the ≤1-chunk **Step/Finish** confinement plus a **separate
activation/promotion** tx (oracle gate + MPFS absence/unicity + selected-store
materialization) — with its own unmeasured bound at each tx's **own** boundary; and
(ii) the **separate rotation advance** — §6a **incoming-set** threshold Ed25519 + the
selected physical-storage update (non-zero-depth MPF update for B/C) + `Data`
boundary — with its own unmeasured bound. Each family's batch bound (candidates B/C)
**MUST be measured directly at its own tx boundary** and **MUST NOT** be assumed
equal to, or bounded by, the #99 value-write `N`.

### 2026-07-11 — NOTE-014 (logical unicity vs physical layout)
Registration unicity is the **fixed logical** MPFS-with-oracle decision (#91 §7c
decision 2). A per-AID UTxO advance store (candidate A) **does not** reopen it —
unicity stays an MPFS absence proof at registration; the per-AID UTxO is only the
promoted advance store. The decision matrix keeps all three physical candidates
compatible with the fixed logical decisions.

### 2026-07-11 — NOTE-015 (decision left open *pending evidence*, not permanently) — **SUPERSEDED by NOTE-021**
**Superseded 2026-07-14 (NOTE-021):** the decision is no longer left open pending
evidence. The operator selected **Candidate A** on the sovereignty invariant, so
there is no evidence-gated decision slice and no "OPEN pre-evidence state." The
historical intent of this note — that #92's deliverable is a *decision*, not a
permanently-open matrix — is honoured by the sovereign decision itself. *Original
text (historical):* this planning record does not select the physical shape; it
fixes the candidate set, the falsifiable criteria, and the evidence provenance, and
leaves the matrix cells `MEASURE`; a later evidence-gated decision slice would fill
the matrix and name one candidate.

### 2026-07-11 — NOTE-016 (thresholds ratified before measurement) — **RESCOPED to A-implementation sizing (NOTE-021)**
**Rescoped 2026-07-14 (NOTE-021):** thresholds-before-measurement is **no longer a
precondition of the #92 decision** (the decision is the sovereignty invariant, not a
threshold contest). The discipline survives **only** for the **downstream
Candidate-A implementation-sizing** work: if that work adopts SLO/cap thresholds,
they are ratified with provenance **before** the A-sizing measurement, never chosen
after seeing a result. It does **not** gate this record, and `accept.sh` no longer
blocks the decision on any B/C threshold ratification. *Original text (historical):*
the matrix "target/budget/bounded/SLO/cap" criteria are not falsifiable until each
names a concrete number, which the decision slice would ratify with provenance before
measuring.

### 2026-07-11 — NOTE-017 (lane assignment is grindable — average ≠ adversarial)
Because `lane = f(cesr_aid)` is a **public, deterministic** function, a
permissionless attacker can **grind** `cesr_aid` values until `f` lands in a
**chosen victim's lane**. Candidate C therefore improves **average / uncoordinated**
contention and emergency latency by ≈K, but **does not** bound the **targeted
worst-case** victim-lane contention or emergency latency to `B/K` — under grinding a
victim lane degrades toward B. C's criteria (C2/C4) are measured **separately for
the average and the adversarial/targeted case**; a fixed K must plan for **skew and
re-shard migration** (changing K or `f` re-homes every AID). The earlier claim that
"an attacker cannot choose a victim's lane" is **withdrawn**.

### 2026-07-11 — NOTE-018 (transient inception token vs steady checkpoint token; Step/Finish ≠ rotation)
Two corrections travel together. (a) **Token lifecycle:** during the multi-tx
inception Step/Finish path, **every** candidate (A included) confines the
intermediate chaining value with a **per-attempt transient** cage/thread token; the
**steady** per-AID checkpoint token (candidate A) is minted/promoted **only after**
Finish + the #91 oracle gate + MPFS absence/unicity — **not** from an inception
`OutputReference`, which would permit concurrent duplicate attempts and would not be
AID-discoverable. A's steady checkpoint still depends on **off-chain indexing of
public chain data** to *discover* the AID's checkpoint UTxO — but that dependency is
**refined forward in NOTE-019** to a **generic exact-asset `(checkpoint_policy_id,
aid_asset_name)` Cardano index lookup** answerable by any generic asset index, **not**
a bespoke/authoritative QVI-owned `AID → UTxO` directory. (b) **Boundary split:** genesis **Step/Finish** (inception
byte-binding/confinement) and the **witnessed incoming-set rotation** check (rotation/checkpoint-
advance) are **different transactions on different paths**; evidence measures the
**registration pipeline** (Step / Finish / activation-promotion) and the **rotation
advance** at their **own** tx boundaries and **never sums disjoint transactions**
into one per-tx budget claim.

### 2026-07-14 — NOTE-019 (Candidate A = minted AID-bound steady checkpoint asset; discovery is generic, not a bespoke QVI DB)
Candidate A's discoverability is refined (A/B/C **remain** evidence candidates — this
clarifies/falsifies A, it does **not** select it). (a) **What is minted** is a
**quantity-one steady checkpoint locator/state token for a registered AID**, **not**
the KERI AID itself, with full asset id **`(checkpoint_policy_id, aid_asset_name)`**.
(b) **`aid_asset_name`** is a canonical, domain-separated, collision-resistant,
**exactly-32-byte** derivation
`blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖ canonical_qualified_aid_bytes)` — computed
with Cardano's **native `blake2b_256` Plutus builtin**, **not** BLAKE3 (BLAKE3 is the
expensive checkpointed `blake3(icp) == cesr_aid` genesis binding #97/#98 measure, and
re-computing it is unnecessary for a cheap Cardano locator label) — from **#91's
canonical qualified CESR AID** (CESR derivation code + the complete 32-byte `cesr_aid`
digest), preserving the **derivation-code/domain distinction**, inventing **no** second
identity encoding, and **not** replacing the genesis `blake3(icp) == cesr_aid` bind;
the exact domain-tag/preimage-encoding is the one residual **#68 pins**. It is
**never** an inception-`OutputReference`-derived token. (c) **`checkpoint_policy_id`
= the applied checkpoint validator's script hash = the checkpoint state output's
payment script hash** (#99 combined mint+spend `targetScriptHash == policyId`) — the
equality **names/binds** the combined script but **does not by itself** make the native
asset non-transferable or pin it to that address; the token is **caged inductively** by
the mint-placement (`+1` into exactly one designated output) + spend-continuation
(exactly one successor at the same address, quantity one) rules, with migration/close
the only exits. (d) The
steady token is minted **exactly once, `+1`**, only after Finish byte binding + the #91
oracle/projection gate + the MPFS absence/unicity proof; the mint places exactly one
token in exactly one `CheckpointStateOutput` and rejects extra names/quantities.
(e) The **current key state lives in the inline `CheckpointDatum`**, not in the token
(the token is the locator); #68 freezes its exact CBOR/wire layout later.
(f) **Normal rotation** is a `delta = 0` state transition (`new.seq = old.seq + 1`,
AID + `aid_asset_name` invariant, one continuing output at the same script address, the
token moved not re-minted); migration and close/`-1`-burn are kept separate. (g)
**Discovery** is therefore a **generic multi-asset `(policy_id, asset_name) → current
unspent output` lookup** answerable by any generic Cardano asset index — the earlier
"A requires a bespoke/authoritative QVI-owned `AID → UTxO` database/index" framing is
**withdrawn**; the falsifiable discovery criterion is **C9** (§5). B/C discovery still
requires an off-chain MPFS state materializer/proof builder — an on-chain root is **not**
free leaf discovery.

### 2026-07-14 — NOTE-020 (cheap native-BLAKE2b locator; inductive caging; inductive downstream trust)
Three bounded corrections to the Candidate-A framing (A/B/C **remain** evidence
candidates — this refines A, it does **not** select it):
(a) **Locator hash is native BLAKE2b, not BLAKE3.** `aid_asset_name :=
blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖ canonical_qualified_aid_bytes)` uses
Cardano's **native `blake2b_256` Plutus builtin**. BLAKE3 is the **expensive, multi-tx
checkpointed** computation #97/#98 measure for the `blake3(icp) == cesr_aid` **genesis
byte-binding**; the steady asset name is a **new, cheap Cardano locator label**, not a
second self-certification, so it must **not** re-compute BLAKE3. The preimage still
carries the **CESR derivation code + the complete 32-byte `cesr_aid`**, so the
derivation-code/domain distinction is preserved; `aid_asset_name` is a deterministic
**label of** the existing KERI AID, **not** a second identity and **not** a replacement
for the fixed genesis bind; **#68** still freezes the exact domain-tag constant and the
canonical preimage encoding.
(b) **The token is caged inductively, not by the hash equality.**
`checkpoint_policy_id == checkpoint_validator_hash` **names/binds** the combined
mint+spend script but does **not** by itself make the native asset non-transferable or
force it to live at that address. Confinement is an **inductive** invariant: the
**mint branch** places exactly `+1` in exactly one designated checkpoint output;
**every spend branch** requires exactly one successor at the **same** designated script
address with the **same** asset at quantity one; **only** the separate migration/close
branches may move to an accepted successor policy/address or burn `-1`.
(c) **Downstream consumers inherit transition facts inductively.** A CIP-31 reference
input is **read, not spent**, so no checkpoint spending validator runs in the consumer
tx; the consumer does **not** replay KERI history, re-verify prior rotations/witness-set
changes, recompute genesis BLAKE3, or (for A) supply an MPF inclusion proof — those are
inherited from the genuine singleton token's mint/spend history. The consumer performs
only a **bounded provenance/state boundary check** (exact `(policy_id, asset_name)`,
quantity one, accepted checkpoint script/version, well-formed inline datum with
AID/sequence binding, active/freeze/lineage). **Application** facts created later stay
application work and split by plane: a **new** dApp payload/action is authorized under
the **authenticated current keys** (schema/business rules alongside) — the checkpoint
**cannot pre-prove a future payload** — while **historical ACDC issuance / TEL status
stays historical** (sealed into the issuer's KEL at that past key state, verifiable
through later rotations; §ACDC boundary correction), **not** re-checked under current
keys. The consumer may trust the **authenticated current key state** after the boundary
check to authorize new actions; it must **not** trust an arbitrary datum merely because
it sits at the same script address.

### 2026-07-14 — NOTE-021 (operator decision: sovereignty selects Candidate A)
**The operator selected Candidate A** (`answers/A-001-thresholds.md`, ratified
2026-07-14) as a **normative security/product decision**, not the winner of a
throughput/capital/cost contest. The **load-bearing, operator-ratified sovereignty
invariant**: unrelated issuers and attacker-created AIDs **cannot contend with,
consume, serialize, or delay** an AID's current-authority checkpoint / rotation /
recovery / re-authorization path, because each AID advances **only** through its own
uniquely-tokenized `(checkpoint_policy_id, aid_asset_name)` UTxO.
- **B is rejected** — a single/global/shared checkpoint-root UTxO serializes unrelated
  identities on one contended UTxO.
- **C is rejected** — a public/grindable lane `f(cesr_aid)` lets hostile AIDs target a
  victim's lane, and makes sovereignty depend on shard machinery.
- **A is selected** — sovereignty holds by construction (own uniquely-tokenized UTxO).

This **supersedes** the evidence-gated selection premise (NOTE-015) and the
threshold-hard-stop (QUESTION-001, NOTE-016 rescoped): B/C threshold ratification and
the filled A/B/C selection matrix **no longer gate** the decision, and `accept.sh` no
longer requires them. **Candidate-A cost/tx-size/min-ADA/batch-fan-in measurements and
the live-boundary smoke remain required as a downstream implementation-sizing gate** —
**never** fabricated, back-filled, or represented as the reason A was chosen. The
B/C **comparison** artifacts are deferred/withdrawn honestly. R-KEL's on-chain
checkpoint classification and the #99 cage invariants are **preserved**.

### 2026-07-15 — NOTE-022 (reopen: normative loss/fork semantics + the superwatcher live-duty contract)
After the first finalization (PR #104 marked ready at `5fd5f2e`), the operator found a
**blocking documentation-consistency gap**: the loss/fork/superwatcher surfaces still
carried the **retired two-independent-state-machines / divergence-burn** framing — most
visibly `docs/design/super-watcher.md`, whose supersession banner sat atop a **still-live
convergence-enforcement-by-burn body** (`trie_key`, "Fork = forfeit", bounty burn) — and
the **loss/recovery and fork/divergence user outcomes were unstated**. The epic owner
(before re-checking the pane hierarchy) reverted the gate-drop (`d3964a3`, `gate.sh`
restored) and returned PR #104 to **draft**. This reopens #92 for a **documentation-only
consistency correction**: the eight-point **loss / fork semantics and superwatcher
live-duty contract** (§"Loss / fork semantics …") is made **normative** and reconciled
across the live docs by a reviewed **DS6** slice. **The sovereign per-AID checkpoint
decision (Candidate A) is unchanged** — `DECISION.md` and the selection stand; this adds
no candidate, no validator, and does **not** re-cut R-FRZ. The correspondence duty
(identity-model §7b, drilled via #90) is a **defined superwatcher duty**, not a "pending
open thread 4," and the generic indexer boundary (liveness only, never identity truth)
stays intact — the superwatcher is **not** an authoritative resolver.

## P1 user story

As a protocol designer ratifying the identity storage model, I read this record
and find (1) an explicit split between the **fixed logical** registration/unicity
decision and the **now-decided physical** advance-storage shape; (2) the
**operator-ratified sovereignty invariant** that selects **Candidate A** — a per-AID
**minted steady checkpoint asset** (`(checkpoint_policy_id, aid_asset_name)`,
discoverable by a **generic** multi-asset lookup, C9) — and the **explicit sovereign
reasoning** rejecting **B** (shared/global UTxO serializes unrelated identities) and
**C** (grindable public lane; sovereignty depends on shard machinery); (3) the
**universal re-authorization** and **ACDC boundary** semantics — rotation makes pending
authorizations stale, every future action re-references the current checkpoint, and
historical ACDC issuance/TEL evidence stays historical (not re-signed under current
keys); (4) a **Candidate-A implementation-sizing + live-boundary measurement plan**
retained honestly as a **downstream implementation gate** — measured at the
**registration pipeline** and **rotation advance** own tx boundaries (never summed),
with the live-devnet smoke and its stated limitation, and **never** fabricated or
presented as the selection reason; (5) every brief.md concern covered; and (6) no
invented numbers — with no disturbance to the R-KEL classification or the #99
invariants.

## ACDC holder user story — historical issuers vs current actors (Candidate A)

As an ACDC holder presenting a credential, **Alice** (her wallet / proof builder)
keeps two evidence paths separate:

1. For each credential issuer, she supplies **historical issuance evidence**: the
   issuer commitment and KEL/TEL anchor at the key state in force when the credential
   was issued, plus current all-TELs non-revocation. She does **not** resolve an
   issuer's current checkpoint merely because that issuer appears in the credential
   chain. Later issuer rotation does not invalidate the historical issuance.
2. For each AID that authorizes a **new action in this transaction** — Alice, a
   sender, officer, transfer agent, or other acting AID — she derives the asset id
   `(checkpoint_policy_id, aid_asset_name)` deterministically from the qualified AID
   (`aid_asset_name = blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖
   canonical_qualified_aid_bytes)`; `checkpoint_policy_id` is protocol/network
   configuration).
3. She resolves each acting AID's current checkpoint UTxO with a **generic
   multi-asset index** (any indexer / local node / sidecar / replicated resolver),
   using cached outrefs with failover — never a bespoke, authoritative QVI-owned
   `AID → UTxO` directory.
4. She supplies those UTxOs as real CIP-31 reference inputs. The validator re-checks
   singleton asset, designated script/version/lineage, inline datum/AID binding, and
   freshness/freeze rules. A stale answer yields retry/failure, not forged authority.
5. The acting AID's `CheckpointDatum` supplies its current weighted keys and sequence.
   Rotation consumes that checkpoint and makes a pending authorization stale; the
   action must be re-signed under the successor state. Historical credentials are not
   re-signed.
6. Because a checkpoint is read as a reference input, no checkpoint spending
   validator runs in the gated transaction. Its accepted mint/spend lineage carries
   the bounded current-authority induction; historical credential verification still
   follows the separate KEL/TEL evidence path.

Criterion **C9** has an explicit **exclusive/authoritative issuer/QVI database
falsifier**. A candidate fails C9 when current-actor checkpoint discovery is not
answerable by a generic exact-asset lookup, or lacks rotation-successor tracking,
migration lineage, stale-result rejection, or closed/tombstone semantics. B/C
answer the same current-actor story via an MPF inclusion proof against a windowed
root plus an off-chain MPFS state materializer/proof builder.

## Functional requirements

- **FR1.** The record **distinguishes the fixed logical** MPFS registration/unicity
  decision (#91 §7c decisions 1 & 2) **from the now-decided physical** R-KEL advance-
  storage shape, in an explicit table, and states that a per-AID UTxO does not
  reopen logical unicity (NOTE-014).
- **FR2.** The record **selects the physical storage shape: Candidate A** — the
  sovereign per-AID uniquely-tokenized checkpoint UTxO — by the **operator-ratified
  sovereignty invariant** (§Operator decision, NOTE-021), records **B and C as
  rejected** with their sovereign reasons and residual risks, and drives the canonical
  docs to carry the decision. The selection is **not** an evidence-gated matrix win and
  does **not** wait on B/C threshold ratification; the earlier "open pending evidence"
  premise is superseded (NOTE-015).
- **FR3.** **Three candidates** are documented: (A, **selected**) per-`cesr_aid`
  sovereign checkpoint UTxO, (B, **rejected**) singleton MPFS checkpoint/root UTxO,
  (C, **rejected**) lane-sharded MPFS — each with a validator-shape sketch and, for the
  rejected pair, its sovereign residual risk.
- **FR4.** The **selection rule is the sovereignty invariant** (unrelated-AID
  isolation), not a cost/throughput matrix; the retained characterization matrix is
  **descriptive**, and any thresholds/measurement discipline it carries applies **only**
  to the **downstream Candidate-A implementation-sizing** work (NOTE-016 rescoped),
  never as a decision precondition.
- **FR5.** **Uniqueness/authenticity** and **how an AID-owned checkpoint is
  located** are covered per candidate, and **discovery trust-minimization is a
  falsifiable matrix criterion (C9)**: exact `(policy_id, asset_name)` lookup,
  rotation-successor tracking, migration/policy-version lineage, stale-result
  rejection, and closed/tombstone semantics — with an A design that depends on an
  exclusive/authoritative issuer/QVI database **rejected**. The consumer's
  **inductive downstream trust boundary** is stated (NOTE-020): a CIP-31
  reference-input read runs **no** checkpoint spending validator and replays **no**
  KERI history / prior rotations / genesis BLAKE3 / MPF proof — those are inherited
  from the singleton token's mint/spend history — leaving only a **bounded
  provenance/state boundary check**. Downstream application work splits by plane: a
  **new** dApp payload/action is authorized under the **authenticated current keys**
  (the checkpoint cannot pre-prove a future payload), while **historical ACDC
  issuance / TEL status stays historical** (issuance sealed into the issuer's KEL at
  that past key state, verifiable through later rotations — §ACDC boundary
  correction), **not** re-checked under current keys; a datum is **not** trusted
  merely for sitting at the same script address.
- **FR6.** **Token/policy-token shape, predecessor/version binding, exact output
  placement, close/burn/migration, and #99 cage-invariant interaction** are covered
  per candidate; #99 invariants are a preservation requirement. The **transient
  inception-cage token lifecycle** is specified exactly (all candidates): mint
  **tied to the consumed attempt input**, Step **preserves exactly one** token, and
  Finish **consumes-and-burns/promotes exactly once** (§Transient inception-cage
  lifecycle).
- **FR7.** **Registration Step/Finish intermediate confinement** and whether
  **concurrent unrelated AIDs can interfere with or consume one another's
  intermediate state** are covered (spike `has_continuing_output` has no thread
  token; confinement is the required unbuilt invariant; **every candidate — A
  included — confines via a per-attempt transient cage/thread token, and A's steady
  checkpoint token is minted only after Finish + oracle gate + MPFS unicity**,
  NOTE-018; C5). The transient token's **failure/abandonment** path is specified: a
  **bounded timeout → reclaim/burn** that **cannot activate or bypass byte binding**,
  with the timeout **ratified before measurement** if it affects the decision (not
  invented).
- **FR8.** **Rotation ordering, same-AID serialization, witnessed incoming-set rotation,
  stale proofs, snapshot/rebuild, batch atomicity, and replay/misbinding rejection**
  are covered per candidate.
- **FR9.** **Permissionless-inception / global-UTxO griefing and emergency-rotation
  latency** are covered; this includes the **transient inception-cage griefing
  surface** — permissionless attackers can **create and abandon many** intermediate
  cage UTxOs, bounded by a **deposit-funded timeout/reclaim/burn** (all candidates,
  §Transient inception-cage lifecycle); **C's `lane = f(cesr_aid)` is grindable, so
  its targeted worst-case is not bounded to B/K (average vs adversarial are separate
  criteria, NOTE-017)**; the **separate freeze path (R-FRZ)** stays visible; the
  record states that **replay protection alone does not give revocation freshness**.
- **FR10.** **Write throughput/contention, state/output growth & min-ADA, datum/
  redeemer & proof sizes, MPFS proof/update work, batching bounds, and off-chain
  coordination cost** are covered per candidate — including the **transient
  inception-cage bloat** (peak concurrent live attempts + abandoned-attempt cost) as
  a state-growth surface distinct from the steady stores (matrix C3b).
- **FR11.** **Migration and downstream consequences for #68, #24, #25, and #44** are
  documented (not absorbed/solved).
- **FR12.** **Honesty boundaries, residual risks, unsupported capabilities, and
  remaining implementation/measurement work** are enumerated; **#99 `Modify N` is
  explicitly not treated as a genesis or checkpoint-advance batch bound**
  (NOTE-013).
- **FR13.** The **live-boundary-smoke limitation** is stated (devnet
  `maxTxExUnits` mem 10× / CPU identical; `evalTxExUnits` hang → declared-not-
  measured; a unit/golden proof does not substitute for the live node boundary).
- **FR14.** An **evidence & measurement plan with provenance** names existing
  evidence honestly and specifies the **whole-transaction-boundary** measurement the
  delegated slice must produce — the **registration pipeline** (Step / Finish /
  activation-promotion) and the **rotation advance** measured at their **own** tx
  boundaries, **never summing disjoint transactions** into one per-tx claim
  (NOTE-018); **no measurements are invented**.
- **FR15.** The record **preserves the R-KEL classification** (on-chain checkpoint
  over settled R-ID, not a watcher-attested mirror) and the fixed genesis/oracle/
  projection decisions; contradictions are escalated, not silently resolved.
- **FR16.** **Candidate A is specified as a minted, AID-bound steady checkpoint
  asset with generic discovery** (NOTE-019), unambiguously and consistently: (a) what
  is minted is a **quantity-one steady checkpoint locator/state token for a
  registered AID** (not the KERI AID), asset id **`(checkpoint_policy_id,
  aid_asset_name)`** with **`aid_asset_name`** a domain-separated, collision-resistant,
  **exactly-32-byte** derivation (via the **native `blake2b_256` Plutus builtin, not
  BLAKE3**) of **#91's canonical qualified CESR AID** preserving
  the derivation-code/domain distinction (no second identity encoding, and no
  re-computation/replacement of the genesis `blake3(icp) == cesr_aid` bind; the exact
  tag/preimage-encoding pinned by **#68**); (b) **`checkpoint_policy_id` = the
  checkpoint validator's script hash = the state output's payment script hash** (#99
  combined mint+spend) — the equality **names/binds** the combined script, but the
  token is **caged inductively** by the mint-placement + spend-continuation rules,
  **not** by the hash equality alone (which does not make a native asset
  non-transferable); (c) the token is minted **exactly once, `+1`**, only after
  Finish + the #91 oracle gate + MPFS unicity, placing exactly one token in exactly
  one **`CheckpointStateOutput`** and rejecting extra names/quantities; (d) the
  **current key state lives in the inline `CheckpointDatum`** (the token is the
  locator, not the key store; **#68** freezes the CBOR/wire layout); (e) **normal
  rotation** is a **`delta = 0`** transition (consume-tip, incoming-set validation, `new.seq
  = old.seq + 1`, AID + `aid_asset_name` invariant, exactly one continuing output at
  the same script address, token moved not re-minted), with **migration** and
  **close/`-1`-burn** kept separate; (f) **discovery** is a **generic `(policy_id,
  asset_name) → current unspent output` lookup** — no bespoke/authoritative QVI
  database — gated by criterion **C9**; and (g) the **ACDC holder user story** is
  stated. The datum/address distinction is made precise (a datum does not own an
  address; the TxOut carrying the inline datum is locked at the script-hash address).

## Success criteria (the sovereign decision + its consistency pass)

- [X] `accept.sh` mechanically asserts the **sovereign** #92 deliverable. Its `final`
  target goes GREEN **only** when **all** hold: **`DECISION.md` records the
  operator-ratified sovereign selection** (`SELECTED_CANDIDATE=A`,
  `REJECTED_CANDIDATES=B,C`, `SELECTION_BASIS=sovereignty`, the sovereignty invariant,
  the B/C sovereign rejection reasons, the operator ratification provenance, non-empty
  residual risks, and the **measurement residual** framed as downstream
  A-implementation sizing); the **canonical docs carry the sovereign per-AID decision**
  (identity-model thread 8 resolved, system-architecture) with the **R-KEL
  classification and #99 cage invariants preserved**; and the structural spec checks
  pass (logical/physical split, three candidates, the Candidate-A minted AID-bound
  steady checkpoint asset with native-`blake2b_256` locator + inductive caging +
  inductive downstream trust boundary + C9 generic-discovery + the QVI-database
  negative guard, universal re-authorization, the ACDC boundary correction, the
  emergency-freeze residual, batched fan-in). It **forbids** representing the decision
  as a measured throughput/capital/cost win and forbids reopening the shape as
  "unselected/open pending evidence." `final` requires **all six DS1–DS6
  repository-consistency documentation slices** (canonical model, ACDC boundary,
  architecture current-auth/discovery, design trust/UX/DeFi/aid, the
  downstream-consequence specs + business-case audit, and the **loss/fork semantics +
  superwatcher live-duty contract**) — it cannot go GREEN while any DS surface stays
  stale. **RED on `origin/main`; GREEN once `DECISION.md` (ticket owner) and every
  DS1–DS6 documentation slice (pair) land.** (Reopened 2026-07-15 for DS6, NOTE-022.)
- [X] The **measurements are honest**: Candidate-A cost/tx-size/min-ADA/batch-fan-in +
  the live-boundary smoke are recorded as a **downstream implementation-sizing gate**,
  **never fabricated, back-filled, or presented as the selection reason**; B/C
  comparison artifacts are deferred/withdrawn honestly.
- [X] `./gate.sh` passes locally at committed HEAD; PR-life `gate.sh` dropped before
  mark-ready (finalization, after epic-owner acceptance). *(Reopened once for the T9216
  CI-link repair — `gate.sh` restored by `revert: restore gate.sh for the DS6 CI-link
  repair slice`, then re-dropped in the final `chore: drop gate.sh (ready for review)`
  commit after the repair + epic acceptance.)*
- [X] Bisect-safe reviewed slices, each carrying a `Tasks:` trailer; fresh GitHub CI green
  (incl. `Docs links`); every commit passes the Conventional-Commit + `Tasks:` gate. The
  canonical/consistency documentation edits (incl. the T9216 CI-link repair) are **reviewed
  pair slices**, not authored by the ticket owner.

## Out of scope (do not implement)

- **Re-opening the storage-shape selection** — it is **decided (Candidate A)** by the
  operator sovereignty invariant (§Operator decision, NOTE-021). Re-deriving it from a
  B/C measurement contest, or leaving it "open pending evidence," is out of scope.
- **Actually performing the Candidate-A implementation-sizing measurements / building a
  validator prototype** — those are a **downstream implementation gate** (behavior-
  changing; a downstream ticket), not authored in this design record; nor is any B/C
  comparison measurement.
- **Re-cutting the emergency-freeze (R-FRZ) mechanism** to a sovereign shape — recorded
  as a downstream residual/dependency (§Emergency freeze), not implemented here.
- Any validator, Haskell, wire-schema, or storage-layout **code**.
- Absorbing **#68** (schema freeze), the full **#24** lifecycle/protocol, **#25**
  proof construction, or **#44** — only their **consequences** are documented.
- Reopening **hybrid genesis, oracle gating, semantic-projection trust, the #91
  teeth state machine, or R-KEL's checkpoint-vs-mirror classification** — fixed
  inputs; a concrete contradiction is escalated to the epic owner.
- An on-chain/off-chain **CESR parser / projection verifier**, the **adjudicator/
  governance-quorum** mechanism, and reverting merged #97/#99 — out of scope.
