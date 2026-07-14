# Feature Specification: R-KEL checkpoint advance-storage & contention model — decision framework (open pending evidence)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/92
Parent epic: https://github.com/lambdasistemi/cardano-keri/issues/21
PR: https://github.com/lambdasistemi/cardano-keri/pull/104

This is a **design-decision ticket**, not implementation. It resolves
`identity-model.md` **open thread 8** ("who pays / contention"): the **physical
storage and contention model for the identity R-KEL checkpoint advance path**.

#92's ultimate deliverable is a **decision + validator-shape sketch**: the ticket
**must select one physical model**, record the rejected alternatives and their
residual risks, and update the canonical docs (`identity-model.md` thread 8,
`system-architecture.md`) with the decision. Planning **begins OPEN pending
evidence** — this record fixes the candidate set, the falsifiable matrix, and the
evidence that will close it — but **OPEN is a pre-evidence state, not the final
state**: a later, evidence-gated **decision slice** fills the matrix, applies the
selection rule, and names the selected candidate. This planning record itself does
not invent the deciding numbers or pick a winner from the framing alone; it lays
the rails for the decision slice to do so.

The deliverable of *this planning record* is (a) the boundary between the
**already-fixed logical** registration/unicity decision and the **still-open (pre-
evidence) physical** advance-storage shape, (b) a comparison of **three** physical
candidates in a **falsifiable decision matrix**, and (c) the **evidence** — whole-
transaction-boundary measurement (the **registration pipeline** and the **rotation
advance** measured at their real, separate tx boundaries) plus a live-devnet smoke
— that will close the matrix. No validator, Haskell, wire-schema, storage-layout,
CESR-parser, or #24 lifecycle code is written here.

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
| **Physical R-KEL *advance* storage shape** | **per-AID UTxO vs singleton MPFS vs sharded/hybrid** | **#92 (this ticket)** | **This is the open decision** |
| Where the AID-owned checkpoint physically lives / is located | candidate-dependent | #92 | **Open** |
| How advances contend, batch, and grow state | candidate-dependent | #92 | **Open** |

A per-AID UTxO advance store **does not remove the logical MPFS registration
gate**: unicity remains an MPFS absence proof at registration (decision 2); the
per-AID UTxO would only be the *advance*-path storage that a registered leaf is
promoted into. A singleton-MPFS advance store already *is* the registration trie.
A sharded store partitions the registration trie. **This record keeps all three
compatible with the fixed logical decisions and lets evidence choose the
physical shape.**

## Candidates (all three carried; none selected here)

Notation: the advancing per-AID checkpoint holds (identity-model.md §6)
`Checkpoint { keys, threshold, next_digest, witnesses, toad, seq }` (and the §7b
`native_sn` binding) — the conceptual key-state, carried on-chain as the inline
**`CheckpointDatum`** (Candidate A); #68 freezes its exact CBOR/wire layout. "Advance" = a witnessed-seal rotation (§4/§6a two-seal
handoff) or a genesis promotion. Reads are **CIP-31 reference-input**,
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
    rotations or two-seal handoffs, **does not** recompute the genesis BLAKE3
    `blake3(icp) == cesr_aid`, and (for Candidate A) **supplies no MPF inclusion
    proof** — those transition facts are **inherited inductively** from the genuine
    singleton token's own mint/spend history (each advance already proved its step at
    the time it was written);
  - the consumer performs only a **bounded provenance/state boundary check**: exact
    `(policy_id, asset_name)`, quantity one, an **accepted checkpoint script/version**
    (payment credential + policy-version lineage), a **well-formed inline
    `CheckpointDatum`** with the expected **AID/sequence binding**, and the
    active/freeze/lineage rules relevant to the protocol;
  - **application-specific facts created later remain application work** — e.g.
    verifying the presented **ACDC/payload signature under the authenticated current
    keys**, plus schema, TEL/revocation, or business rules. **The checkpoint cannot
    pre-prove a future payload.**

  So the consumer **may trust the authenticated current key state** the datum carries
  **after** the bounded boundary check succeeds; it **must not** trust an arbitrary
  datum **merely because** someone sent it to the same script address (a stray output
  at that address, lacking the singleton asset and AID/sequence binding, fails the
  boundary check).
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
  the witnessed **two-seal handoff** (§6a, fixed upstream); (iii) requires
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
  **that AID's own UTxO only** — no global contention. Two-seal handoff (§6a)
  checked against the *stored* `(witnesses, toad)` then advanced once. Stale-root
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

## Decision matrix — falsifiable selection criteria

Each criterion has a **falsifier** that *eliminates* a candidate. Cells marked
`MEASURE` are **not filled here** — they are produced by the delegated
whole-transaction-boundary measurement slice (§Evidence). **No values are invented
in this record.**

**Thresholds are ratified before measurement, not after.** Criteria that read
"target / budget / bounded / SLO / cap" below are **not yet falsifiable** until each
names a concrete number (mainnet ex-unit budget, advances/block SLO, capital-lock
cap, emergency-latency SLO, read-cost cap, downstream-recut bound). The decision
slice **must first ratify these thresholds** — with provenance, routing any operator
decision through `questions/` — and only **then** measure against the **fixed**
thresholds. **Choosing a threshold after seeing a candidate's result is forbidden**
(NOTE-016; `accept.sh` guards the ordering: ratified thresholds carry a
provenance/timestamp predating the measurement).

| Criterion (falsifier) | A per-AID UTxO | B singleton MPFS | C lane-shard |
|---|---|---|---|
| **C1a Registration-pipeline per-tx budget fit** — each registration tx measured at its **own** boundary: Step(s), Finish, and activation/promotion (oracle gate + MPFS absence/unicity + selected-store materialization, incl. A's post-Finish steady-token mint) each fit mainnet 14 M mem / 10 G CPU. *Falsifier: any single registration tx cannot fit at realistic proof depth.* | MEASURE | MEASURE | MEASURE |
| **C1b Rotation-advance per-tx budget fit** — the *separate* rotation-advance tx (§6a two-seal threshold Ed25519 + selected physical-storage update at realistic MPF depth + continuing output/token + `Data` boundary) fits mainnet 14 M mem / 10 G CPU at N=1. *Falsifier: cannot fit N=1 at realistic depth. Disjoint transactions are never summed into one per-tx claim.* | MEASURE | MEASURE | MEASURE |
| **C2 Sustained honest advance throughput ≥ ratified SLO** — measured **separately** for the **average/uncoordinated** and the **targeted/adversarial** case (grinding a victim lane in C). *Falsifier: measured advances/block below the ratified SLO and batching cannot reach it within the C1b budget, in whichever case that criterion requires.* | high (parallel) | MEASURE (A12-bound) | MEASURE (average K-way; targeted victim ≈ single-lane) |
| **C3 State/min-ADA growth per 10⁶ active AIDs ≤ ratified capital-lock budget.** *Falsifier: projected locked min-ADA × active population exceeds the ratified budget (A's min-ADA is reclaimable on close/burn — count active, not cumulative).* | MEASURE (O(#active AIDs)) | O(1) UTxO | O(K) UTxO |
| **C3b Transient inception-cage bloat & cleanup ≤ ratified bloat budget** — the shared per-attempt transient cage (all candidates) under permissionless spam: **peak concurrent live attempts** and **abandoned-attempt cost** (min-ADA held + reclaim/burn cost), with the timeout/reclaim path self-funding. *Falsifier: peak concurrent transient UTxOs or unreclaimable abandoned-attempt min-ADA exceeds the ratified bloat budget, or the reclaim/burn path is not deposit-funded.* | MEASURE (transient cage) | MEASURE (transient cage) | MEASURE (transient cage) |
| **C4 Emergency-rotation latency under contention ≤ ratified SLO** — measured for both the **average** lane and a **grinding-targeted victim** lane (C). *Falsifier: cannot settle a preempting rotation within the ratified SLO; for C the targeted-victim latency is **not** assumed `B/K` and must be measured under grinding.* | low | MEASURE (highest) | MEASURE (avg ≈B/K; targeted → toward B) |
| **C5 Step/Finish confinement realizable with zero cross-AID interference** — a **required, unbuilt design** the delegated prototype/harness must demonstrate, not an implemented fact. *Falsifier: concurrent unrelated inceptions can consume one another's intermediate `cv`.* | VERIFY (per-attempt transient token) | VERIFY (transient cage token) | VERIFY (transient cage token) |
| **C6 Per-action read cost (CIP-31 ref + proof size) ≤ ratified cap.** *Falsifier: proof/redeemer size or read exec-units exceed the ratified cap.* | minimal (datum read) | MEASURE (MPF proof size, asymptotics per actual impl) | MEASURE (per-lane MPF proof size, asymptotics per actual impl) |
| **C7 #99 cage invariants preserved** (predecessor/version continuity, output confinement, exact burn/lifecycle) — the integrated candidates are **unbuilt**, so this cannot read "yes" here: the delegated prototype/harness **MUST prove every inherited #99 invariant** at the candidate's stated scope. *Falsifier: any invariant cannot be reproduced.* | PROVE (per-AID cage) | PROVE (registry-scoped) | PROVE (per-lane) |
| **C8 Migration/downstream cost to #68/#24/#25/#44 within ratified re-cut bound & bisect-safe.** *Falsifier: any downstream re-cut exceeds the ratified bound or is not expressible as a versioned, additive change.* | MEASURE | MEASURE | MEASURE |
| **C9 Trust-minimized generic discovery** — an AID's current checkpoint state is located by an **exact `(policy_id, asset_name) → current unspent output` lookup** answerable by **any** generic Cardano asset index (indexer/node/sidecar/replica), and the design **tracks rotation successors**, **follows migration/policy-version lineage**, **rejects stale/forged resolver answers against the ledger** (singleton asset + designated script address + inline datum/AID binding), and gives **closed/tombstone** state an unambiguous discovery story — the resolver supplies availability/freshness, **not** identity truth. *Falsifier: discovery depends on an exclusive/authoritative issuer/QVI database, OR lacks exact-asset lookup, rotation-successor tracking, migration lineage, stale-result rejection, or closed-state semantics.* This is a **design-property proof (no numeric threshold)** — recorded `PASS`/`FAIL` with a real evidence class, **not** `class=proved`. | VERIFY (generic `(checkpoint_policy_id, aid_asset_name)` asset lookup; §5) | VERIFY (MPF inclusion vs windowed root **+ off-chain MPFS state materializer/proof builder**) | VERIFY (per-lane MPF inclusion **+ off-chain MPFS state materializer/proof builder**) |

**Selection rule (run by the decision slice, after thresholds are ratified and the
matrix is filled):** eliminate every candidate a falsifier kills — **including the C9
trust-minimized-discovery falsifier** (a candidate whose discovery depends on an
exclusive/authoritative issuer/QVI database, or lacks exact-asset lookup, rotation
tracking, migration lineage, stale-result rejection, or closed-state semantics, is
eliminated); among survivors pick the one dominating on C2/C3/C4 at the lowest C6/C8
cost. If two survive within
measurement noise, prefer the **smaller downstream re-cut** (C8) and record the tie
honestly. The decision slice **must end with exactly one selected candidate**, the
rejected alternatives and their residual risks recorded, and the canonical docs
updated. **This planning record does not run that rule — it fixes the rule and the
evidence that feeds it; a selection asserted here, without the evidence, would be
fabrication.**

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
- **Rotation ordering, same-AID serialization, witnessed two-seal handoff, stale
  proofs, snapshot/rebuild, batch atomicity, replay/misbinding.** Same-AID
  serialization: A per-UTxO, B global, C per-lane. Two-seal (§6a): Seal W checked
  vs stored `(witnesses,toad)`, Seal K vs the just-endorsed `(W',toad')`, one
  advance. Stale proofs/window + snapshot-rebuild: dissolve in A, depth-10 window
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

## Evidence & measurement plan (provenance — no invented numbers)

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

### What MUST be measured (the delegated slice that closes the matrix)

**Order of work (thresholds before measurement, NOTE-016).** The slice **first
ratifies** the concrete thresholds every "target/budget/bounded/SLO/cap" criterion
names (C2 SLO, C3 capital-lock cap, C4 emergency-latency SLO, C6 read-cost cap, C8
re-cut bound), with provenance and any operator decision routed through
`questions/`, **then** measures against those **fixed** thresholds. Choosing a
threshold after seeing a result is forbidden.

For **each candidate**, produce measured `C1a/C1b/C2/C3/C4/C6/C8` at the **actual
transaction boundary of each distinct transaction**, not a primitive in isolation
and **never by summing disjoint transactions into one per-tx claim**:

1. **Registration pipeline** — measure each of its transactions at its **own**
   boundary: the ≤1-chunk **Step(s)**, **Finish**, and **activation/promotion**
   (oracle gate + MPFS absence/unicity + selected-store materialization, incl. A's
   post-Finish steady-token mint/promotion). Each uses the **per-attempt transient
   cage/thread token** for confinement. Report per-tx ex-units/size (C1a).
2. **Rotation advance** — a **separate** tx exercising the §6a **two-seal threshold
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

- **No candidate is selected in *this planning record* — but #92 must select one.**
  The matrix is open **pending evidence**; selection is the job of the later
  evidence-gated decision slice (fill the matrix, apply the rule, name the winner,
  record rejected alternatives/residual risks, update canonical docs). Any "A/B/C is
  best" statement **in this record**, before that evidence, would be fabrication;
  **leaving the matrix permanently open would fail #92's deliverable.**
- **The advance path is unbuilt and unmeasured, and its transactions are
  distinct.** The registration pipeline (Step/Finish confinement → Finish → oracle +
  MPFS unicity + store materialization) and the **separate** rotation-advance tx
  (two-seal + MPF update) have never been built or measured; #97 and #99 measure
  disjoint fragments. **Genesis Step/Finish and the rotation two-seal are different
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
(ii) the **separate rotation advance** — §6a **two-seal** threshold Ed25519 + the
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

### 2026-07-11 — NOTE-015 (decision left open *pending evidence*, not permanently)
Per the ticket's charter, **this planning record** does not select the physical
shape: it fixes the candidate set, the falsifiable criteria, and the evidence
provenance, and leaves the matrix cells `MEASURE`. **OPEN here is a pre-evidence
state, not #92's final state** — the GitHub deliverable is a **decision +
validator-shape sketch**, so a later **evidence-gated decision slice** fills the
matrix (from the whole-transaction-boundary measurement + live-devnet smoke),
applies the selection rule, **names exactly one selected candidate**, records the
rejected alternatives and residual risks, and updates the canonical docs. Selection
without that evidence is forbidden; *permanent* non-selection would fail the ticket.

### 2026-07-11 — NOTE-016 (thresholds ratified before measurement)
The matrix criteria that read "target / budget / bounded / SLO / cap" (C2/C3/C4/C6/
C8) are **not falsifiable until each names a concrete number**. The decision slice
**ratifies** those thresholds first — mainnet ex-unit budgets, an advances/block
SLO, a capital-lock cap, an emergency-latency SLO, a read-cost cap, a
downstream-recut bound — **with provenance**, routing any operator decision through
`questions/`, and only **then** measures against the fixed thresholds. **Choosing a
threshold after seeing a candidate's result is forbidden**, and `accept.sh` checks
that ratified thresholds predate the measurement.

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
byte-binding/confinement) and the **witnessed two-seal** check (rotation/checkpoint-
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
tx; the consumer does **not** replay KERI history, re-verify prior rotations/two-seal
handoffs, recompute genesis BLAKE3, or (for A) supply an MPF inclusion proof — those are
inherited from the genuine singleton token's mint/spend history. The consumer performs
only a **bounded provenance/state boundary check** (exact `(policy_id, asset_name)`,
quantity one, accepted checkpoint script/version, well-formed inline datum with
AID/sequence binding, active/freeze/lineage). **Application** facts created later stay
application work (the presented ACDC/payload signature under the **authenticated current
keys**, plus schema/TEL/business rules) — the checkpoint **cannot pre-prove a future
payload**. The consumer may trust the **authenticated current key state** after the
boundary check; it must **not** trust an arbitrary datum merely because it sits at the
same script address.

## P1 user story

As a protocol designer ratifying the identity storage model, I read this record
and find (1) an explicit split between the **fixed logical** registration/unicity
decision and the **open physical** advance-storage shape; (2) **three** concrete
candidates — a per-AID **minted steady checkpoint asset** (`(checkpoint_policy_id,
aid_asset_name)`, discoverable by a **generic** multi-asset lookup, C9), singleton
MPFS, and lane-sharded hybrid — each with its
uniqueness/token/confinement/rotation/griefing/cost story; (3) a **falsifiable
decision matrix** (including the C9 trust-minimized-discovery falsifier) whose
deciding cells are honestly marked `MEASURE`/`VERIFY` (open **pending evidence**, with
a later evidence-gated decision slice that will select one model);
(4) an evidence plan that measures the **registration pipeline** and the **rotation
advance** at their **own** tx boundaries (not a single fictitious combined tx, and
never summed) with a live-devnet smoke and its stated limitation; (5) every brief.md
concern covered; and (6) no invented numbers and no *premature* selection **in this
record** — while the record makes explicit that #92's final deliverable is a
**selected model** from the decision slice — with no disturbance to the R-KEL
classification or the #99 invariants.

## ACDC holder user story — generic checkpoint-asset discovery (Candidate A)

As an ACDC holder presenting a credential, **Alice** (her wallet / proof builder)
needs the **current weighted signing keys** of each relevant **issuer AID** without
contacting each QVI:

1. For each issuer AID, she **derives the asset id** `(checkpoint_policy_id,
   aid_asset_name)` deterministically from the AID (`aid_asset_name =
   blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖ canonical_qualified_aid_bytes)`, the
   **native `blake2b_256` Plutus builtin**, not BLAKE3;
   `checkpoint_policy_id` is protocol/network configuration).
2. She **resolves each current checkpoint UTxO** with a **generic multi-asset index**
   (any indexer / local node / sidecar / replicated resolver), using **cached
   outrefs with failover** — no bespoke, authoritative, QVI-owned `AID → UTxO`
   database, and no QVI online at presentation time.
3. She **supplies the resolved UTxOs as real CIP-31 reference inputs**, and the
   verifier/validator **re-checks** each against the ledger — **singleton asset**,
   **designated script address**, **inline `CheckpointDatum`/AID binding**, **policy
   lineage**, and freshness/freeze — so a **stale index answer** yields
   **retry/failure, not forged authority**.
4. She thereby obtains the **current weighted issuer keys** directly from the datum.
   **After an issuer rotation** (`delta = 0`; `new.seq = old.seq + 1`), the **same
   asset id** points to the **successor UTxO** and the **refreshed `CheckpointDatum`**
   supplies the new keys — Alice does **not** consult a QVI-owned directory.
5. Because each checkpoint is a **reference input (read, not spent)**, **no checkpoint
   spending validator runs** in her transaction and she needs **no KERI replay, no
   prior-rotation / two-seal re-verification, no genesis-BLAKE3 recompute, and no MPF
   inclusion proof** — those transition facts are **inherited inductively** from the
   singleton token's mint/spend history, leaving only the **bounded boundary check** of
   step 3. She then does the **application** work the checkpoint **cannot pre-prove**:
   **verify the presented ACDC's signature under those authenticated current keys**,
   plus schema and TEL/revocation. She may trust the **authenticated current key state**
   after the boundary check; she must **not** trust a datum merely because it sits at
   the same script address.

This story is what criterion **C9** falsifies for any candidate whose discovery
depends on an exclusive/authoritative issuer/QVI database or lacks exact-asset lookup,
rotation-successor tracking, migration lineage, stale-result rejection, or
closed/tombstone semantics. (B/C answer the same story via an MPF inclusion proof
against a windowed root **plus** an off-chain MPFS state materializer/proof builder.)

## Functional requirements

- **FR1.** The record **distinguishes the fixed logical** MPFS registration/unicity
  decision (#91 §7c decisions 1 & 2) **from the open physical** R-KEL advance-
  storage shape, in an explicit table, and states that a per-AID UTxO does not
  reopen logical unicity (NOTE-014).
- **FR2.** *This planning record* **keeps the physical storage decision open pending
  evidence** — no candidate is selected here and deciding matrix cells are marked
  `MEASURE` (NOTE-015) — **but records that #92's final deliverable is a selected
  model**: a later evidence-gated decision slice fills the matrix, applies the
  selection rule, names exactly one candidate, records rejected alternatives +
  residual risks, and updates the canonical docs. OPEN is a **pre-evidence** state,
  not the final state.
- **FR3.** **Three candidates** are compared: (A) per-`cesr_aid` checkpoint UTxO,
  (B) singleton MPFS checkpoint/root UTxO, (C) a **concrete** hybrid/shard/lane
  candidate (lane-sharded MPFS), each with a validator-shape sketch.
- **FR4.** A **decision matrix with falsifiable criteria** (each criterion carries
  an elimination falsifier) whose "target/budget/bounded/SLO/cap" thresholds are
  **ratified with provenance before measurement** (NOTE-016), plus the selection
  rule applied only post-evidence to **name exactly one candidate**.
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
  provenance/state boundary check**; the presented ACDC/payload signature under the
  **authenticated current keys** (plus schema/TEL/business rules) stays **application
  work** the checkpoint cannot pre-prove, and a datum is **not** trusted merely for
  sitting at the same script address.
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
- **FR8.** **Rotation ordering, same-AID serialization, witnessed two-seal handoff,
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
  rotation** is a **`delta = 0`** transition (consume-tip, two-seal handoff, `new.seq
  = old.seq + 1`, AID + `aid_asset_name` invariant, exactly one continuing output at
  the same script address, token moved not re-minted), with **migration** and
  **close/`-1`-burn** kept separate; (f) **discovery** is a **generic `(policy_id,
  asset_name) → current unspent output` lookup** — no bespoke/authoritative QVI
  database — gated by criterion **C9**; and (g) the **ACDC holder user story** is
  stated. The datum/address distinction is made precise (a datum does not own an
  address; the TxOut carrying the inline datum is locked at the script-hash address).

## Success criteria (measurable; satisfied by later slices, not this run)

- [ ] `accept.sh` (authored in the tasks slice, not here) mechanically asserts the
  **final** #92 deliverable and is **RED now / GREEN only after the decision slice**.
  It goes GREEN **only** when **all** hold: evidence provenance exists, the material
  matrix cells are **filled** (no longer `MEASURE`) from the delegated
  whole-transaction-boundary measurement, **exactly one** candidate is selected, the
  selection rule is applied with rejected alternatives + residual risks recorded, and
  the **downstream/canonical docs carry the decision**. It **must not** assert
  `MEASURE` cells or absence-of-selection as the success state (that would make #92's
  deliverable impossible). It **separately forbids a selection *without* evidence** —
  a named candidate with unfilled cells or missing provenance is RED. It also checks
  the structural FRs (logical/physical split + table, three named candidates,
  falsifiable matrix + ratified thresholds, per-candidate concern coverage, the
  **transient inception-cage lifecycle & cleanup** — mint tied to attempt input,
  Step-preserves-one, Finish-burns/promotes-once, bounded deposit-funded
  timeout/reclaim, plus its C3b bloat/abandoned-attempt criterion — the **Candidate A
  minted AID-bound steady checkpoint asset** — `(checkpoint_policy_id, aid_asset_name)`
  with the domain-separated 32-byte `aid_asset_name` derivation, #99 combined
  policy-id=script-hash, the `CheckpointStateOutput` shape, the `delta = 0` rotation
  transition — the **C9 generic-discovery criterion + falsifier** with a **negative
  guard rejecting the bespoke/authoritative QVI-owned `AID → UTxO` database framing**,
  the ACDC holder user story, #68/#24/#25/#44
  consequences, evidence-provenance section, R-KEL-classification-preserved /
  #99-not-a-bound NOTE-013). **RED on `origin/main` and RED at this planning HEAD;
  GREEN only at the decision slice's HEAD.**
- [ ] The decision matrix's `MEASURE` cells are filled **only** from a delegated
  measurement of the **registration pipeline** (Step / Finish / activation-promotion)
  and the **rotation advance** (two-seal Ed25519 + non-zero-depth MPF update + `Data`
  boundary) **at their own tx boundaries** — never summing disjoint transactions —
  and **only against thresholds ratified beforehand** (NOTE-016), with stated
  provenance — **no fabricated numbers**.
- [ ] A **named live-boundary smoke** submits a real checkpoint-advance tx on the
  tx-tool devnet (`withDevnet`) and asserts the node Phase-1/Phase-2 outcome, with
  its limitation recorded; a unit/golden-only proof does not satisfy this.
- [ ] `./gate.sh` passes locally at HEAD before mark-ready; PR-life `gate.sh`
  dropped before mark-ready.
- [ ] Bisect-safe reviewed slices, each carrying a `Tasks:` trailer; fresh GitHub
  CI green.

## Out of scope (do not implement)

- **Selecting the physical storage shape *in this planning record*** — selection is
  **in #92's scope** but **evidence-gated**: it happens in the later decision slice,
  after threshold ratification and the delegated measurement, **not** here and
  **not** from the framing alone. (Leaving it permanently unselected is **not** an
  acceptable outcome — see FR2 / NOTE-015.)
- Any validator, Haskell, wire-schema, or storage-layout **code** (measurement
  harness/prototypes are dispatched to the driver+navigator pair, not authored by
  the ticket owner).
- Absorbing **#68** (schema freeze), the full **#24** lifecycle/protocol, **#25**
  proof construction, or **#44** — only their **consequences** are documented.
- Reopening **hybrid genesis, oracle gating, semantic-projection trust, the #91
  teeth state machine, or R-KEL's checkpoint-vs-mirror classification** — fixed
  inputs; a concrete contradiction is escalated to the epic owner.
- An on-chain/off-chain **CESR parser / projection verifier**, the **adjudicator/
  governance-quorum** mechanism, and reverting merged #97/#99 — out of scope.
- `plan.md`, `tasks.md`, and `accept.sh` — not created in this planning run.
