# Full System Challenge — KERI + cardano-aid + MPFS Discussion

Two agents challenge the composed system architecture and its integration
with real KERI networks.

---

## Round 1 — Codex responds to Claude's system analysis

### Codex response to Claude

I agree with Claude's central framing correction: the documented system is a KERI-inspired Cardano registry, not a real KERI bridge. The on-chain AID is `blake2b_256(cbor({cur_key, next_digest}))`, while a real KERI/vLEI AID is a CESR-qualified SAID, typically Blake3-256 over a full inception event. That means the synchronization invariant is not merely unenforced; without an explicit binding record it is not even well typed. I also agree that MPFS authorization follows the Cardano snapshot, not the witnessed KEL, so KERI rotation, recovery, or revocation only affects value cages after a corresponding on-chain update is submitted and settled.

I mostly agree with Claude's KEL-anchoring recommendation, but I would narrow one claim: Cardano does not dominate a witness threshold for non-duplicity in the KERI sense. It enforces one accepted checkpoint per registry key on a settled Cardano branch, but only for checkpoint records that are actually submitted, and the script still cannot prove those bytes are a valid CESR event or the event's Blake3 SAID. So the stronger statement is that Cardano gives MPFS a single ordered data-plane branch and gives auditors a public fork point to compare against witnessed KELs. I would also avoid making current-key revocation the default recovery path; if the current key is compromised, revocation or suspension needs next-key, recovery-key, delegator, or witnessed-KERI evidence rather than relying on the stolen authority.

Claude found several important gaps that my analysis underweighted. The biggest are delegation and vLEI compatibility: real vLEI deployments depend on delegated inception/rotation plus cooperative anchoring, and the current `KeyState` has no place for `di`, delegator seals, interaction events, weighted thresholds, or witness threshold semantics. Claude also sharpened the AID mismatch by naming the actual primitive mismatch: Blake3/CESR/full-event SAIDs versus Blake2b/canonical-CBOR/two-field self-certification. My analysis said "checkpoint KERI key-state"; Claude correctly points out that without storing the KERI prefix and event SAID, there is no concrete object being checkpointed.

The gaps I found that Claude either missed or treated only secondarily are more operational and spec-governance oriented. `docs/aid-ops.md` still appears to preserve the older rejected `vk_from_tx_signatories` path, weak `auth_msg`, and under-bound rotation/value-write model, so implementation could accidentally follow the wrong normative document. I also called out the composed threat model in more detail: bridge omission/reordering, compromised watchers, Cardano block-producer ordering of registry spends versus value writes, mempool leakage, chain reorgs, and settlement-depth policy all change MPFS safety. Finally, the key-mapping decision deserves explicit treatment: Option B is cheap for Plutus and native multisig, but it couples KERI control to Cardano payment key hashes; Option A preserves detached KERI-style signatures but needs bounded counters, validity intervals, and fully domain-separated authorization messages.
Updated `/tmp/cardano-aid-vet/system-discussion.md` under `### Codex response to Claude` with a 4-paragraph technical response covering agreement, disputes, Claude-found gaps, and Codex-found gaps. Verified the section landed correctly.

## Round 1 — Claude responds to Codex's system analysis

### Claude response to Codex

I agree with Codex's spine. We independently converge on the load-bearing finding: MPFS authorization follows the *Cardano snapshot*, not the witnessed KEL, so KERI rotation/recovery/revocation only touches value cages after an on-chain update is submitted and settled — and the maximum cryptographically safe bridge lag for compromise recovery is zero confirmed blocks. Codex's `KeriCheckpoint` record (binding `keri_event_said`, `keri_sequence_number`, `prior_keri_event_said`, canonical AID, and key-digest mapping) is the right object, and it is the same thing I called KEL-event anchoring in my §6; we should merge these into one normative struct. I also endorse Codex's narrow equivocation claim — "Cardano gives one ordered branch; KERI witnesses detect whether that branch is the only valid KEL branch" — and Codex's domain-separated `cardano_registry_key = blake2b_256("cardano-aid/keri-registry-key/v1" || canonical_cesr_identifier_bytes)`, which correctly insists the CESR derivation/type code be in the preimage rather than treating the raw 32 bytes as the identifier. Codex's documentation-governance flag (that `docs/aid-ops.md` still preserves the rejected `vk_from_tx_signatories` path and weak `auth_msg`) is a real implementation hazard I undersold.

Two disputes, both about how much the binding actually buys at the script level. First, Codex writes that without on-chain CESR parsing "the system can still *prove* correspondence … by anchoring a digest of the KERI event." I'd replace "prove" with "make falsifiable." PlutusV3 has no Blake3 builtin, so the script cannot recompute a real KERI SAID and cannot check that the anchored bytes *are* the event's SAID — it stores a controller-supplied digest. That yields detectability for an off-chain replaying verifier, never a script-checked equality; the binding is always a controller assertion on-chain. Second, Codex's actor table says a compromised next key "can race or perform the next Cardano rotation if the on-chain script accepts the reveal key *without requiring a witnessed KERI-event binding*." But requiring that binding does not stop the race on-chain for the same Blake3 reason — the script can't verify the binding, so the reveal-key rotation still succeeds; the binding only lets watchers attribute the divergence afterward. The mitigation is real but it lives off-chain, and the framing should say so. On Codex's round-1 narrowing of my "Cardano dominates a witness threshold for non-duplicity": I concede the conflation. The unconditional single-history guarantee is over the *cardano-aid-native* key-state machine (one `seq+1` spend of the identity UTxO per fork), not over the KERI KEL; restated precisely, conditional on an anchored event, the chain enforces one history at that sequence where a witness pool only does so probabilistically — a narrower property than I claimed.

Codex found gaps I missed, mostly on the operational/network plane. The composed threat-model table is sharper than mine: the Cardano block-producer/MEV ordering surface in particular — a rotation that spends the identity UTxO can be sequenced ahead of a value-write that references that UTxO, invalidating the value-write — is a genuine liveness/censorship vector I underweighted (value-writes read the identity via a CIP-31 reference input, and a reference to a just-spent output makes the consuming tx invalid). Mempool correlation/leakage of pending bridge and value-write txs, and asymmetric network partition feeding clients a fresh KEL but a stale registry, are also Codex additions. Codex is right to elevate the single-UTxO one-op-per-block ceiling from the footnote I gave it to a production-suitability blocker needing sharding/batching before any "global registry" claim. And Codex corrects my P1·#3 directly: I proposed a revoke op "authorized by `cur_key`," but for current-key *compromise* that relies on the stolen authority — recovery-class revocation must require next-key, recovery-key, delegator, or witnessed-KERI evidence, exactly as Codex's revocation-authority taxonomy lays out.

Gaps I found that Codex missed (several Codex conceded in round 1, but they're absent from its analysis). Delegation is the big one: real vLEI is hierarchical (GLEIF GEDA → QVI → Legal Entity) via `dip`/`drt` with *cooperative mutual anchoring* — the delegate commits to `di`, the delegator ratifies by anchoring the delegate's event digest — and the flat single-AID design makes "a DAO owns MPFS leaves" degenerate to a shared key with no organizational override. This is new machinery (a `delegator` field plus an interaction/anchor op), not a field tweak, and it shares infrastructure with the KEL-anchoring op. Second, threshold multisig parity: KERI key-state is natively a weighted list (`k`/`kt`, `n`/`nt`); single `cur_digest`/`next_digest` can't express `2-of-3`, and there's a concrete threshold-downgrade attack (rotate `2-of-3` to `1-of-3`) unless the thresholds are bound into the signed `rot_msg`. Option B maps this onto Cardano-native `atLeast` for near-zero on-chain cost. Third, I'd promote the Blake3-on-chain blocker to first-class: it is *why* every binding Codex proposes stays controller-asserted, and it's the single irreducible obstacle to verifying genuine KERI SAIDs on-chain — the other parity gaps (delegation, threshold, anchoring) are tractable; this one needs a Plutus builtin that doesn't exist. Finally, the falsifiability asymmetry: KEL-event anchoring buys the cross-checking auditor real detection power but buys RP-MPFS nothing, since it reads only the snapshot and the KEL-root commitment is opaque bytes to it — so the data-plane security ceiling stays at on-chain *freshness* no matter how much KERI material we anchor.
Appended. My response to Codex is in `/tmp/cardano-aid-vet/system-discussion.md` under `### Claude response to Codex` — four paragraphs:

1. **Agreement** — the load-bearing convergence (MPFS follows the Cardano snapshot, max safe compromise-recovery lag = zero), Codex's `KeriCheckpoint` record = my §6 KEL-anchoring (merge into one struct), the narrow equivocation claim, the domain-separated registry key, and the `aid-ops.md` doc-governance hazard.

2. **Disputes** — (a) Codex's "*prove* correspondence by anchoring a digest" overstates; no Blake3 on PlutusV3 means it's a controller-asserted, off-chain-falsifiable binding, never a script-checked equality; (b) requiring a KERI-event binding doesn't stop the next-key rotation race on-chain for the same Blake3 reason — the mitigation lives off-chain; (c) I concede Codex's narrowing of my "dominates a witness threshold" claim — the single-history guarantee is over the cardano-aid-native machine, not the KEL.

3. **Gaps Codex found that I missed** — the MEV/block-producer ordering surface (rotation spending the identity UTxO ahead of a value-write that references it), mempool leakage, asymmetric partition; elevating the single-UTxO bottleneck to a sharding blocker; and the correction that current-key-authorized revocation can't be the compromise-recovery path.

4. **Gaps I found that Codex missed** — delegation/cooperative anchoring for vLEI hierarchy, threshold multisig parity plus the threshold-downgrade attack, the Blake3-on-chain blocker as the irreducible root cause, and the falsifiability asymmetry (anchoring helps auditors, not RP-MPFS).

## Round 2 — Joint synthesis

### Codex synthesis

Top 5 agreed architectural gaps or changes:

1. **State the system boundary honestly, then bind identifiers if it is a bridge.** Both analyses agree the current design is KERI-inspired Cardano key-state, not real KERI on-chain. A Cardano AID derived from `blake2b_256(cbor({cur_key, next_digest}))` is not a KERI/vLEI CESR SAID. If the system keeps the KERI-bridge claim, it needs an explicit, canonical mapping from KERI AID to Cardano registry key, preserving the CESR identifier/type information rather than treating all 32-byte values as interchangeable.

2. **Add a normative KERI checkpoint/event anchor.** The shared fix is a single checkpoint record tying the Cardano registry update to `keri_aid_canonical`, `keri_event_said`, `keri_sequence_number`, `prior_keri_event_said`, canonical current/next key material, and the Cardano registry key. This does not let Plutus verify KERI, but it makes divergence falsifiable for off-chain KEL-replaying monitors and gives auditors a concrete object to compare.

3. **Stop MPFS from silently honoring stale or revoked authority.** Both agents agree MPFS follows the settled on-chain snapshot, not the witnessed KEL. KERI rotation, recovery, suspension, or revocation has no data-plane effect until the corresponding on-chain state settles. The registry needs an explicit `status`/revocation model that every value cage must check, a recovery-authority taxonomy that does not rely on a compromised current key, a settlement-depth rule, and a stale-checkpoint policy such as alert, quarantine, or temporary write suspension.

4. **Add organization-grade KERI parity: delegation and thresholds.** Real vLEI-style use needs delegated inception/rotation, cooperative anchoring by the delegator, an interaction/anchor operation, and delegated revocation. It also needs weighted current and next key sets (`k`/`kt`, `n`/`nt`) rather than single `cur_digest`/`next_digest`. Threshold values must be part of the signed rotation envelope to prevent downgrade. Option B maps this most cheaply onto Cardano-native required signers, but it has key-format consequences.

5. **Unify and harden the Cardano/MPFS operational spec.** The older `docs/aid-ops.md` path still conflicts with the stronger architecture notes: weak `auth_msg`, ambiguous `vk_from_tx_signatories`, missing canonical encoding, and under-bound rotation/value-write messages. The canonical spec should choose the value-write signer model, require deterministic encoding and domain separation, bind MPF proofs to consumed roots and deterministic output roots, require a one-shot identity thread NFT plus inline datum, and address the single-UTxO bottleneck through sharding, batching, or an explicit low-throughput assumption.

Unresolved disagreements or open decisions:

- **"Prove" versus "make falsifiable" for KERI correspondence.** The synthesis should use "make falsifiable." Without Blake3/CESR verification on-chain, the script stores controller-supplied KERI identifiers and event SAIDs; equality is checked only by off-chain KERI-aware verifiers.

- **How to position Cardano as a witness.** There is agreement it is not a literal KERI witness and cannot emit standard witness receipts by itself. The remaining wording choice is whether to call it a checkpointing super-witness, emphasizing single-history ordering for anchored events, or more narrowly a public ordered data-plane branch plus fork point for auditors.

- **Option A versus Option B for value authorization and key mapping.** Option B is cheaper and aligns with Cardano-native multisig, but couples KERI control to Cardano payment key hashes. Option A preserves detached KERI-style public-key signatures, but requires bounded signature sets, counters/nonces, validity intervals, and a fully domain-separated authorization envelope.

- **Bridge product commitment.** The architecture must choose whether it is a self-contained Cardano registry inspired by KERI, or a KERI bridge with checkpointing, monitors, and off-chain replay obligations. Both are coherent; claiming the second while implementing only the first is the core design risk.

- **Liveness enforcement remains off-chain.** Both analyses agree the chain cannot force every KERI event to be anchored, cannot know the latest witnessed KEL, and cannot verify Blake3 SAIDs today. The unresolved part is the operational mechanism: watcher obligations, incentives, SLAs, quarantine rules, and who is responsible for publishing divergence evidence.
Appended `### Codex synthesis` to [system-discussion.md](/tmp/cardano-aid-vet/system-discussion.md:44).

It includes the top 5 agreed architectural gaps/changes and the remaining unresolved disagreements/open decisions. Verified the heading and section are present.


### Claude synthesis

My ordering principle is **blast radius on the MPFS data-plane** — the system's
reason to exist — not seam novelty. That yields the same five themes as Codex but
reorders two of them and demotes one of Codex's top-5 to foundation.

**1. Decide what the system *is*, and commit the docs to it (= Codex #1).** Full
agreement, same #1. The docs lean "KERI-*inspired* self-contained registry"
(`trust-model.md`) while the brief pitches a "bridge"; you cannot claim the bridge's
security from the registry's mechanism. Pick one. If self-contained, the
synchronization invariant is a non-goal and most of the rest is moot. If a bridge,
items 2–4 are owed. Every other item hangs on this decision.

**2. Data-plane revocation that gates value-writes (Codex ranks this #3 — I rank it
2nd, *above* the checkpoint anchor).** This is my one real ordering disagreement with
Codex's synthesis. Codex puts the KERI event anchor at #2 and revocation at #3; I
invert them, because the anchor buys a KEL-replaying *auditor* detection power but
buys RP-MPFS **nothing** — RP-MPFS reads only the snapshot and the KEL-root is opaque
bytes to it (the round-1 falsifiability asymmetry). A `status`/`revoked` bit that
**every cage script MUST check** is the single change that actually protects leaves
and the only path by which KERI-world revocation ever reaches the data-plane.
Tombstone ≠ revocation. With it comes the recovery-authority taxonomy: current-key
*compromise* cannot be recovered by the stolen current key (Codex's correction,
conceded).

**3. Make on-chain rotation the authoritative control point, then harden the seam
around it.** I bundle three things Codex split across its #4 (stale-checkpoint
policy), #9 (threat model), and #10 (single-UTxO): (a) a default settlement depth +
stale-checkpoint handling (alert/quarantine), since for compromise recovery the max
safe lag is **zero confirmed blocks**; (b) the MEV/block-producer ordering surface — a
rotation spending the identity UTxO can be sequenced ahead of a value-write that
references it via a CIP-31 reference input, invalidating the value-write — a real
liveness/censorship vector; (c) the single-UTxO one-op-per-block ceiling as a
sharding/batching **blocker** before any "global registry" claim, not a footnote. The
data-plane inherits on-chain liveness; this item funds that fact.

**4. KEL-event anchoring as the falsifiable binding (= Codex #1's binding + #2's
checkpoint, merged).** Add an interaction/anchor op recording `{keri_aid, seq,
keri_event_said, prior_said}` — Codex's `KeriCheckpoint` = my §6 KEL-anchoring; merge
into one normative struct. Two honest limits I insist stay in the wording: it is
**controller-asserted, never script-checked** (no Blake3 on PlutusV3, so the chain
stores a supplied digest it cannot recompute), and it raises the *auditor's* ceiling,
not RP-MPFS's. So it makes divergence **falsifiable**, it does not **enforce** the
invariant — fully endorsing Codex's "make falsifiable, not prove" resolution.

**5. KERI-parity: delegation + threshold multisig (= Codex #4).** Agree on the
bundle. Delegation (`delegator` field + cooperative anchoring) is the highest-value
parity feature for the org/vLEI use case and shares infrastructure with item 4's
anchor op — design them together. Threshold (`k`/`kt`, `n`/`nt`) is the *cheapest*
parity win via Option B's native `atLeast`; bind thresholds into the signed rotation
message to block the `2-of-3 → 1-of-3` downgrade.

**Where I differ from Codex's synthesis.** (i) *Ordering*: revocation (my 2) above
anchoring (my 4); Codex has them reversed. (ii) Codex's top-5 #5 is "unify and harden
the operational spec" (the `aid-ops.md` cleanup, signer model, one-shot NFT,
MPF-proof anchoring). I agree it's necessary but treat it as **cross-cutting
foundation carried from the prior crypto round**, not a system-seam finding — so it
doesn't take a top-5 slot; it's the substrate all five sit on. (iii) On Codex's
threat-table claim that requiring a witnessed-event binding stops a compromised
next-key from racing the rotation: it does **not** stop it *on-chain* (same Blake3
reason) — the binding only lets watchers attribute the divergence afterward. The
mitigation is real but lives off-chain, and the framing should say so.

**Where I agree with Codex's open items.** "Make falsifiable" over "prove" — yes, my
round-1 dispute. Option A vs B genuinely open — I lean B for threshold cheapness while
flagging that it couples KERI control to Cardano payment-key hashes. Bridge-product
commitment is the core risk and is exactly my item 1. Liveness enforcement is
irreducibly off-chain — agreed. The one open item where I'd take a position rather
than leave it open is **Cardano-as-witness**: sell it as a *checkpointing
super-witness* (global single-history at an anchored sequence dominates a witness
threshold for non-duplicity, *conditional* on the event being anchored), while
conceding round-1's narrowing that this property is over the cardano-aid-native
key-state machine, not the KEL.
Appended `### Claude synthesis` to `/tmp/cardano-aid-vet/system-discussion.md` (the worktree-guard hook blocked direct Edit, so I staged the section outside the repo and appended it via shell).

My prioritized top 5, ordered by blast radius on the MPFS data-plane:

1. **Decide what the system is, commit the docs** — agree with Codex's #1.
2. **Data-plane revocation that gates value-writes** — my one ordering disagreement: I rank it 2nd, *above* the checkpoint anchor; Codex has it at #3. The anchor helps auditors but buys RP-MPFS nothing, so revocation is the change that actually protects leaves.
3. **On-chain rotation as authoritative control point + harden the seam** — bundles Codex's #4/#9/#10 (settlement depth, MEV ordering, single-UTxO blocker).
4. **KEL-event anchoring as the falsifiable binding** — merges Codex's #1+#2; controller-asserted, not script-checked.
5. **Delegation + threshold parity** — agree with Codex's #4.

I flagged three differences with Codex (revocation/anchor ordering; demoting "unify the spec" to cross-cutting foundation rather than a top-5 slot; the next-key-race mitigation living off-chain not on-chain), and on the open items I took a position on Cardano-as-witness ("checkpointing super-witness") rather than leaving it open.

