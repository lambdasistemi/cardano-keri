# Consistency & Completeness Vetting — Canonical Permissionless Model

Cold vet of the current "canonical permissionless model" design docs. Primary
lens: internal consistency and completeness. Severity = impact on
implementability/correctness.

Counts: **Critical 5 · High 8 · Medium 9 · Low 4.**

---

## Confident defects

### C1. `trie_key` is derived from a singleton shape it will never actually have (list-shaped KeyState freeze contradiction)

- **Severity:** Critical
- **Locations (both sides):**
  - Singleton derivation, stated as normative everywhere:
    `aid-model.md` §trie_key derivation: `trie_key = blake2b_256(cbor({cur_pubkey, next_digest}))`; `overview.md` §Identity Registry (same); `identity-ops.md` §Inception on-chain check 1 (same); `veridian-bridge.md` §Inception tx check 1 (same); `blake2b256-requirement.md` (same).
  - Requirement that the *frozen* shape be list-shaped and threshold-capable: `business-cases/index.md` §The factored core item 1 ("the schema shape is frozen into the identity key — it must be list-shaped from v1… with a `delegator` field reserved"); `aid-model.md` §"Scope change: list-shaped KeyState"; `overview.md` §"Scope change: list-shaped KeyState"; `roadmap.md` M1 ("The shape is frozen into `trie_key` at inception, so it must be right from v1").
- **The problem:** Every normative derivation formula hashes exactly two scalar fields, `cur_pubkey` and `next_digest`. The factored core insists the *frozen* commitment must instead cover a list of weighted keys, a threshold, and a reserved `delegator`. No document gives the list-shaped CBOR preimage: what is hashed for a k-of-n AID? The singleton "1-of-1 degenerate case" is asserted but never shown to be the `n=1` instance of the list formula — and it cannot be, because `blake2b_256(cbor({cur_pubkey, next_digest}))` ≠ `blake2b_256(cbor({keys:[cur_pubkey], ...}))`.
- **Why it blocks implementation:** The single most-cited on-chain check (inception derivation, seq-0 binding, front-run proof, the whole aid-model security argument) is specified against a shape the design says must never ship. An implementer cannot write the inception validator: redeemer fields, CBOR map keys, and hash preimage are all undefined for the mandated shape. Frozen at inception "and cannot be retrofitted," so getting this wrong is unrecoverable.
- **Suggested resolution:** Pick ONE canonical list-shaped preimage now and rewrite *every* derivation occurrence to it. Show the 1-of-1 instance explicitly and prove the singleton examples are that instance byte-for-byte. Until done, mark all singleton `trie_key`/`inc_msg`/`KeyState` text illustrative-only.

### C2. Super-watcher burn *removes* the leaf; the tombstone invariant says a leaf is never removed and `trie_key` uniqueness holds forever

- **Severity:** Critical
- **Locations (both sides):**
  - Removal: `super-watcher.md` §Burn transaction, check 5 ("Remove `trie_key` from trie, return deposit to tx submitter"); sequence diagram note "trie_key entry removed from registry"; §Deposit mechanics ("forfeited permanently on burn").
  - Never-removed invariant: `identity-ops.md` §Close ("The leaf is **not removed** — it remains in the trie… forever"), §Duplicity freeze ("permanently embedded in the trie"); `overview.md` §Identity operations ("A closed or frozen leaf **remains in the trie forever**… A `trie_key` can never be re-registered"); `trust-model.md` §On-chain guarantees ("registered at most once… holds over the registry's whole lifetime").
- **The problem:** Burn deletes the leaf, so the inception absence proof for that `trie_key` succeeds again → it **can** be re-registered, breaking the "registered at most once over the whole lifetime" invariant and the tombstone model. Also, deposit disposition diverges across terminal events: burn → to watcher; duplicity-freeze → "deposit stays locked" (`identity-ops.md`); close → refunded. Divergence and duplicity are semantically similar fork offenses with opposite bond outcomes.
- **Why it blocks implementation:** Two validators enforce mutually exclusive post-conditions on the same leaf. Either removal is allowed (uniqueness invariant false, every "cannot re-register" security claim collapses) or not (burn cannot be built as specified).
- **Suggested resolution:** Make burn a tombstone transition (`Diverged` status) not a delete; specify one deposit-disposition table across close / duplicity-freeze / divergence-burn; reconcile whether divergence and duplicity are the same forfeiture class.

### C3. Emergency-freeze on-chain checks reference `reveal_key`, which is not in the freeze message or marker, and there is no freeze redeemer

- **Severity:** Critical
- **Locations:** `identity-ops.md` §Emergency freeze. `freeze_msg` = `{domain, network_id, freeze_policy_id, freeze_thread_token, trie_key, seq}` — no `reveal_key`. On-chain checks 2–3 use it: "`blake2b_256(reveal_key) == leaf.key_state.next_digest`… `Ed25519.verify(reveal_key, freeze_msg, sig)`". `FreezeMarker` = `{trie_key, seq, cur_pubkey_hash, next_digest}` — no `reveal_key`. `veridian-bridge.md` WASM `buildFreezeRedeemer(trie_key, reveal_key, sig, …)` carries it, but `identity-ops.md` defines no freeze **redeemer** at all.
- **The problem:** The freeze redeemer shape is undefined; `reveal_key` (needed by checks 2–3) is carried by no on-chain structure the normative doc defines. Additionally `reveal_key` is not among `freeze_msg` fields, so the signature does **not** bind the revealed key — contradicting the rotation doc's own at-length argument that a possession signature must bind the key it reveals.
- **Suggested resolution:** Add a `FreezeRedeemer { trie_key, reveal_key, sig, seq, id_inclusion_proof }` to `identity-ops.md`; put `reveal_key` inside the signed `freeze_msg`.

### C4. Emergency freeze burns the pre-rotation secret with no state advance — converts a one-key compromise into a two-key compromise

- **Severity:** Critical
- **Locations:** `identity-ops.md` §Emergency freeze (freeze authorized by `reveal_key` = committed next key; marker only suspends value-writes for current seq; "dissolves… once the rotation lands"); `aid-model.md` §Pre-rotation ("After rotation reveals `next_key`, the window between submission and inclusion exposes `next_key`"; "both keys compromised… identity is lost"); `veridian-bridge.md` §Emergency rotation workflow.
- **The problem:** Freeze reveals `reveal_key` (the next key) in a signed message **without advancing seq**. The thief holds `cur_key`; the owner has just published `next_key`. Both keys are now known. The only escape is the later rotation, which the workflow says "may be delayed by main registry contention." Freeze marker and rotation are on two different UTxOs and cannot be one atomic transaction, so the exposure window is unavoidable — exactly the "both keys compromised, no recovery" state.
- **Why it endangers correctness:** The emergency channel meant to *save* a compromised identity structurally worsens the compromise the moment it is used.
- **Suggested resolution:** Authorize freeze with a *separate dedicated freeze key* committed at inception (not the pre-rotation next key); or require freeze+rotation atomic; or document freeze as single-use, mandatorily-followed-by-rotation, and quantify the exposure window as a first-class risk.

### C5. Deposit is simultaneously "protocol-defined minimum / immutable" and "controller-chosen variable convergence bond"

- **Severity:** Critical
- **Locations (both sides):**
  - Fixed/immutable: `operational.md` §ADA inception deposit ("minimum ADA deposit… immutable across rotations"); `veridian-bridge.md` §Inception tx ("protocol-defined minimum"); `identity-ops.md` inception check 4 (`>= deposit_amount`).
  - Variable: `super-watcher.md` §Deposit mechanics ("Allows variable deposit sizes — controllers choose their own convergence bond"), §Economic alignment (5/20/100/1000 ADA table), "Option B (fixed protocol-wide deposit)… rejected."
- **The problem:** `super-watcher.md` explicitly adopts variable and rejects fixed; the operational/bridge docs describe a fixed protocol minimum. Different economic models, different validator logic, different watcher incentive tables.
- **Suggested resolution:** State one deposit model and align all four docs.

### H1. `identity_root` used in two irreconcilable senses; appears in `inc_msg` before the identity exists; typed inconsistently

- **Severity:** High
- **Locations:** `inc_msg`/`auth_msg` carry `identity_root` (`identity-ops.md`, `veridian-bridge.md`, `value-auth.md`); registry datum is a **sliding window** `RegistryDatum { roots : List<ByteArray> }` (`overview.md`, `value-auth.md`). Typed `ByteArray[32]` in `inc_msg`, `ByteArray` (untyped) in `auth_msg`.
- **The problem:** (a) Inception signs `inc_msg` containing the pre-state `identity_root`, but the window has many roots and inception is given no window tolerance (unlike value-writes); a concurrent inception moves the root and stales the signature. (b) `auth_msg.identity_root` is one root while the cage accepts "any root in the window" — the doc never says the cage must check `auth_msg.identity_root ∈ window` or `== proof root`.
- **Suggested resolution:** Define inception window tolerance; specify the cage rule relating `auth_msg.identity_root`, proof root, and window; unify to `ByteArray[32]`.

### H2. Value-write `auth_msg` omits the freeze root, though the freeze check is mandatory and `seq`-scoped

- **Severity:** High
- **Locations:** `value-auth.md` §Option A `auth_msg` binds `identity_root`, `value_input_root`, `value_output_root` — not the freeze root. Signer-resolution step 3 requires "no active `FreezeMarker`."
- **The problem:** The detached signature doesn't commit to the freeze state it's authorized against. A relayer can submit a valid signed `auth_msg` against a freeze snapshot that omits an existing marker; the signature still verifies. Because the marker is `seq`-scoped and `auth_msg` carries `key_seq`, a stale-but-valid same-seq signature can be replayed during the freeze window — defeating the emergency-freeze guarantee precisely in the mode (Option A) used when a third party submits later.
- **Suggested resolution:** Add `freeze_root` (or freeze-nonce) to `auth_msg`; require the cage to verify the absence proof against that pinned root.

### H3. Duplicity freeze verifies both events against `cur_pubkey`, but a KERI fork is not generally signed by the live current key

- **Severity:** High
- **Locations:** `identity-ops.md` §Duplicity freeze checks 2–4 (both events verified with `leaf.key_state.cur_pubkey`; `proof.seq == leaf.key_state.seq`; events are "rotation event bytes"); `super-watcher.md` (duplicity = two conflicting events at the same seq).
- **The problem:** A rotation event at seq N is signed by the establishment key at seq N, not necessarily the *current* on-chain `cur_pubkey`. A fork discovered after the chain advanced (seq M>N) cannot be verified — the chain holds no historical keys ("full KEL history… not stored"). As written the check only catches a fork at the exact live seq with the live key, and is unclear about which key signs a rotation.
- **Suggested resolution:** Specify which key signs a rotation event and how the validator obtains it; if only live-seq duplicity is on-chain-provable, say so and route historical forks off-chain.

### H4. Two mechanisms both claim to answer "controller forks Cardano vs KERI," with different authorization and outcomes

- **Severity:** High
- **Locations:** `super-watcher.md` (burn: permissionless, deposit→watcher, leaf removed) vs. `identity-ops.md` §Duplicity freeze (permissionless proof, deposit locked, `FrozenFatal` tombstone). `veridian-bridge.md` §Convergence enforcement points only at super-watcher.
- **The problem:** "Rotate on KERI but not Cardano" (super-watcher's motivating case) is *not* KERI duplicity (no two conflicting events), so the duplicity-freeze path doesn't apply — yet both docs describe punishing the same fork with different outcomes (removal+bounty vs. tombstone+locked). Compounds C2.
- **Suggested resolution:** Enumerate terminal offenses (close, KERI-duplicity, registry-divergence) as distinct transitions with distinct authorizations/outcomes/deposit dispositions in one table.

### H5. `FreezeMarker.cur_pubkey_hash` is dead data; freeze-registry insert/replacement semantics undefined

- **Severity:** High
- **Locations:** `identity-ops.md` §Emergency freeze `FreezeMarker.cur_pubkey_hash : ByteArray[28]`; checks 1–5 never use it. No rule for duplicate freeze attempts, absence precondition, or overwrite.
- **The problem:** A committed field with no consumer; insert semantics (insert vs upsert, idempotence, absence precondition) undefined, unlike inception. Value cages check "no active marker" via absence proofs, so presence/replacement rules are correctness-relevant.
- **Suggested resolution:** State what `cur_pubkey_hash` is checked against or delete it; define freeze-marker insert preconditions.

### H6. Close (and duplicity/emergency freeze) have on-chain check lists but no redeemer definitions; completeness drifts across the five ops

- **Severity:** High
- **Locations:** `identity-ops.md` §Close check 1 needs an inclusion proof but no close redeemer/proof field is defined; `veridian-bridge.md` gives Inception and Rotation redeemer blocks only — Close, Duplicity-freeze, Emergency-freeze have none. WASM `buildCloseRedeemer(trie_key, sig, inclusion_proof)` carries a proof the normative spec never lists.
- **Suggested resolution:** Add normative redeemer blocks for Close, Duplicity-freeze, Emergency-freeze mirroring Inception/Rotation.

### H7. "Business pick only selects a last-mile adapter" is contradicted by core components each pilot case needs but the core doesn't provide

- **Severity:** High
- **Locations:** `roadmap.md` headline; `business-cases/index.md` §factored core vs. per-case §3–4.
- **The problem:** SPO delegation needs an **Identified-pools registry** (separate MPF cage, own key space, cold-key sig, own lifecycle) and a **Delegation-state UTxO** (`spo-delegation.md` §3) — neither is in the seven core items, both load-bearing. Security tokens need a `stake_credential ↔ trie_key` admission mapping and variant (b) is a whole new authoritative register, not an adapter (`security-tokens.md` §3). Institutional contracts need a **re-designation transition** as a first-class template state (`institutional-contracts.md` §4). These M4 pilots depend on components not scheduled in M1–M3.
- **Suggested resolution:** Promote the identified-pools registry, admission-mapping, and re-designation transition into core deliverables, or soften the "adapter-only" framing.

### H8. Reserved `delegator` field frozen into `trie_key` but type/semantics/KERI-`dip` interaction undefined

- **Severity:** High
- **Locations:** `business-cases/index.md` item 1; `aid-model.md`/`overview.md` scope-change notes; `institutional-contracts.md` §1 (defers KERI-level `dip/drt`); `regulated-defi.md` §4.
- **The problem:** A value frozen into the identity key that is "reserved" but undefined — type, nullability, on-chain checks all unspecified, and its only would-be consumer (KERI-level delegation) is deferred. Reserving a field inside a frozen hash preimage with no semantics is the exact "cannot be retrofitted" trap: adding a delegator to an existing AID later is impossible.
- **Suggested resolution:** Define `delegator` fully now or remove it from the frozen preimage and carry delegation via a mutable KeyState field / separate registry.

### M1. `next_digest` (singular) vs. multi-key pre-rotation for k-of-n is unspecified

- **Severity:** Medium
- **Locations:** All specs carry one `next_digest`; C1's list mandate implies a set. `aid-model.md` §Pre-rotation and `identity-ops.md` §Rotation are singleton.
- **The problem:** For k-of-n, does rotation reveal all n next keys, a quorum? Can the threshold change at rotation (KERI allows)? The rotation checks don't generalize to a set.
- **Suggested resolution:** Specify multi-key rotation semantics as part of C1.

### M2. Threshold / weighted-multisig edge cases entirely unaddressed

- **Severity:** Medium
- **Locations:** Threshold KeyState mandated (`business-cases/index.md` item 1; each case §4) with no validation rule anywhere.
- **The problem:** No stated rule for zero weights; weights not summing as assumed; duplicate keys; `threshold > sum(weights)` (unsatisfiable, permanently bricked yet occupies a `trie_key`); `threshold == 0`; 1-of-1 degenerate (see C1); empty key set; empty next-key set. Frozen at inception, so a malformed threshold is unrecoverable — possibly not even closable.
- **Suggested resolution:** Define an inception-time well-formedness predicate: non-empty keys, no dups, weights > 0, `0 < threshold <= sum(weights)`, matching next-key cardinality; specify k-of-n close/rotation authorization.

### M3. `seq_to` disagreement between rotation redeemer field list and checks; transcript can't express increment

- **Severity:** Medium
- **Locations:** `rot_msg` carries `seq_to` (`identity-ops.md`); `veridian-bridge.md` Rotation redeemer omits `seq_to` but its check 4 references it; `IntentTranscript.seq` is a single number.
- **Suggested resolution:** Add `seq_to` to the rotation redeemer field list; clarify transcript `seq` is the target.

### M4. "`cesr_aid` signed to prevent front-run" overstates — defends Attack A only, not the more damaging Attack B

- **Severity:** Medium
- **Locations:** `identity-ops.md` inception comment; `aid-model.md` §Inception security (Attack A vs. Attack B "Signing `inc_msg` does nothing here").
- **The problem:** Signing prevents poisoning a victim's in-flight material (A) but gives zero protection against squatting a well-known `cesr_aid` with one's own keys (B) — the worse attack for vLEI (squat GLEIF's prefix). The security story rests entirely on off-chain KEL resolution, yet `cesr_aid` stays a first-class stored field every admission flow must never trust.
- **Suggested resolution:** Cross-reference Attack B at the inception comment; reconsider storing `cesr_aid` on-chain at all.

### M5. `KeyState`/status restated in four places with drifting field semantics; no `Diverged` status for burn

- **Severity:** Medium
- **Locations:** `overview.md`, `aid-model.md`, `super-watcher.md`, `identity-ops.md`. `super-watcher.md` describes `deposit` as "release on burn or close"; `operational.md` says "close only." Status enum (`Active`/`FrozenFatal`/`Closed`) has no burn/divergence state (see C2).
- **Suggested resolution:** Make `aid-model.md` §KeyState the single normative source; others link, not restate.

### M6. Amaru doc self-flagged as stale, but its superseded oracle-writer claims still live only there

- **Severity:** Medium
- **Locations:** `amaru-integration.md` top warning vs. its "Two models"/"missing for ACDC" tables ("single trusted oracle writer / per-company, single-writer") contradicting the permissionless plane (`overview.md`).
- **The problem:** A normative-listed doc is caveated as describing a retired model, yet its comparison tables are the sole home of several integration claims; readers can't tell which rows survived.
- **Suggested resolution:** Rewrite the oracle-writer rows or move the doc to historical and stop listing it as normative.

### M7. TEL revocation registry (Layer 2) is required by every case but undesigned — and simultaneously called "unsolved" and "ships M1"

- **Severity:** Medium
- **Locations:** `overview.md` Layer 2; `roadmap.md` M1 (#30); `amaru-integration.md` §missing ("no revocation registry… Designing the on-chain TEL is the real new work, and nobody has done it yet"); every business-case §4 (all-TELs cascade); `defi-gate.md`/`vlei.md` present it as a working "Layer 2 TEL registry proof."
- **The problem:** Layer 2's leaf shape, issuer-authorization, MPF key derivation, root layout, and cascade-proof construction are unspecified, yet it's the hardest/most-valuable component (self-admitted) and gates every case. "Unsolved" (amaru) vs. "M1" (roadmap) is unreconciled.
- **Suggested resolution:** Add a TEL design doc before M1 exit or reschedule.

### M8. Hop bound flips between 3 and 4 across docs; the retired 3-hop diagram remains in the primer

- **Severity:** Medium
- **Locations:** `business-cases/index.md` item 2 / `roadmap.md` M2 ("hop bound 4, parameterized"); `defi-gate.md` still shows "GLEIF → QVI → LE → Individual" (3); `regulated-defi.md`/`security-tokens.md`/`institutional-contracts.md` ("four ACDCs"); `vlei.md` 4-level hierarchy calls the ECR path three.
- **Suggested resolution:** State the parameterized bound with a per-credential-type table (OOR=4, ECR=3); update `defi-gate.md`'s diagram/labels.

### M9. WASM/SDK/IntentTranscript surface is entirely singleton — contradicts the list-shaped mandate on the security-critical signing display

- **Severity:** Medium
- **Locations:** `veridian-bridge.md` §IntentTranscript (single `curPubkey`/`nextDigest`/`seq`); WASM `computeTrieKey(cur_pubkey, next_digest)` and all builder signatures singleton.
- **The problem:** The "show the user what they sign" surface cannot display a k-of-n key set, so a threshold inception/rotation intent cannot be verified by the user (see C1).
- **Suggested resolution:** Redefine WASM/SDK signatures and IntentTranscript for list-shaped KeyState alongside C1.

### L1. `cesr_aid` input named two ways (`inception_event` vs `cesr_inception_event`), serialization undefined

- **Severity:** Low
- **Locations:** `aid-model.md`, `veridian-bridge.md`, `blake2b256-requirement.md`.
- **Suggested resolution:** Define the exact byte input once.

### L2. `POSIXTime` (auth_msg) vs `Slot` (IntentTranscript) for validity windows; no types glossary

- **Severity:** Low
- **Locations:** `value-auth.md` `auth_msg.valid_from/until : POSIXTime`; `veridian-bridge.md` `IntentTranscript.validityInterval : { from: Slot; to: Slot }`.
- **The problem:** Cardano validity intervals are slot-based; mixing POSIXTime invites the time-to-slot conversion hazard.
- **Suggested resolution:** Pick one; add a types glossary.

### L3. Window depth stated only in prose in one doc ("depth 10")

- **Severity:** Low
- **Locations:** `overview.md` (`root_t-k`), `value-auth.md` ("depth 10"), `operational.md` (silent). Affects H1's inception staleness.
- **Suggested resolution:** Fix the constant in one place; relate it to single-op-per-block throughput.

### L4. `op_hash`/`CageOp` under-specified; `counter` vs `nonce` naming

- **Severity:** Low
- **Locations:** `value-auth.md` (`op_hash`, `counter`); `veridian-bridge.md` (`op : CageOp`); `business-cases/index.md` item 4 ("nonce").
- **Suggested resolution:** Define `op_hash` input and the counter's uniqueness domain (per-trie_key monotonic vs random).

---

## Questions / uncertainties

- **Q1 (freeze atomicity):** Can freeze marker and rotation ever be atomic given two separate UTxOs/registries? If not, C4's exposure window is unavoidable — acceptable and quantified? (Not found.)
- **Q2 (inception under contention):** With one identity op/block, how do N concurrent inceptions for different `trie_key`s serialize, and does each loser re-sign `inc_msg` because `identity_root` moved (H1)? The ~1 op/20s claim doesn't address re-sign amplification.
- **Q3 (super-watcher status):** `super-watcher.md`/`vlei.md` gap-table say the burn is *not trustless* without Blake3/CESR and needs a challenge period "chosen first," yet `veridian-bridge.md` §Convergence enforcement states convergence "is proposed to be enforced by the protocol." Commitment or open hypothesis? The three docs hedge differently.
- **Q4 (register-as-cage vs value-auth):** `security-tokens.md` variant (b) is "one cage write mutating two leaves" where sender authorizes but receiver must be *admitted* (not sign). Expressible in the current single-owner value-write model? Unclear.
- **Q5 (scoped-override vs "cannot forge"):** Factored-core item 6 and `security-tokens.md` §6 both flag that issuer freeze/seize "contradicts the epic's headline" and "must be reconciled." Flagged repeatedly, never actually reconciled or designed (only named, #40). Where is the authorization model?
- **Q6 (KERI event key extraction):** Both burn (check 4) and duplicity-freeze (checks 3–4) verify a KERI event signature on-chain while the design says CESR parsing is out of scope on-chain. Super-watcher admits it "trusts the extraction"; duplicity-freeze doesn't acknowledge the same gap.
- **Q7 (close for k-of-n):** Close returns the deposit on a `cur_pubkey` signature. For k-of-n, whose quorum closes, and to which `refund_address`? Undefined.

---

## Overclaims

- **O1.** "Most open decisions are use-case-invariant; the business pick only selects a last-mile adapter." (`roadmap.md`, `business-cases/index.md`.) Contradicted by H7: M4 pilots need an identified-pools registry, delegation-state UTxO, stake↔trie_key mapping, and a first-class re-designation transition — none in the "invariant" M1–M3 core.
- **O2.** "The shape is frozen into `trie_key`… a single key is the 1-of-1 degenerate case." Asserted settled; but no list-shaped preimage exists and singleton examples are provably not the 1-of-1 instance of any list formula (C1). Future-proofing is unestablished: `delegator` reserved-but-undefined (H8), and no room to add v2 fields to a frozen hash (recovery key, threshold-semantics change, post-quantum migration) — "cannot be retrofitted" is a liability, not a feature.
- **O3.** "The oracle is necessary-not-sufficient… cannot forge." Undercut by the design's own repeated admission (factored-core item 6; `security-tokens.md` §6) that a scoped issuer freeze/seize power *must* be reintroduced and is never specified; plus H2 (Option-A envelope doesn't bind freeze freshness → same-seq replay during the freeze window).
- **O4.** "The full derivation chain is on-chain verifiable today… An on-chain script can verify the full chain." (`blake2b256-requirement.md`.) Overstated: the `cesr_aid = blake2b_256(inception_event)` link "proves nothing" on-chain (`aid-model.md` Attack B, `trust-model.md`) since events are public. Only `next_digest`/`trie_key` links are authoritative.
- **O5.** "Cardano provides… structural duplicity prevention." (`vlei.md`.) The chain prevents `trie_key` re-registration, not KERI duplicity — detection is off-chain (`trust-model.md`) and on-chain duplicity-freeze can only verify live-seq forks (H3).
- **O6.** "Ratified 2026-07-07; revisit only if fee-level griefing proves real." (`identity-ops.md`.) Permissionless duplicity submission framed as settled sits next to the near-identical super-watcher burn framed as "not trustless without Blake3" (`vlei.md`, `roadmap.md` M5).
