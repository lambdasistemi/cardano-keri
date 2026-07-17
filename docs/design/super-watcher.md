# Super Watcher: Permissionless Cross-Plane Relayer & Evidence Submitter

!!! note "Live role — a relayer + evidence submitter, not a truth oracle"
    The live super-watcher role is a **first-class, permissionless cross-plane relayer and
    evidence submitter** spanning **KERI ↔ Cardano** and the **credential-status (R-TEL)
    mirror** — **not** the automatic divergence-burn convergence enforcer this page was
    originally written around. Identity is KERI-sovereign (one witnessed KEL); the Cardano per-AID
    checkpoint is a globally ordered, **spend-linearized projection of current authority**,
    **not a second independently sovereign identity history**. For a witnessed AID it cannot
    advance without threshold receipts, and it can lag. The retired automatic
    divergence-burn / `trie_key` / "Fork = forfeit" mechanics are quarantined, in the past
    tense, in the
    [historical appendix](#historical-appendix-the-retired-divergence-burn-design) at the
    foot of this page.

## The two-plane relay problem

The witnessed [KERI](https://github.com/WebOfTrust/ietf-keri) KEL is the sole identity
state machine; Cardano carries a per-AID **checkpoint** that projects the current authority
KERI has settled. This page formerly described the two as independently advancing machines
sharing inception material — that framing is **superseded**: the checkpoint is a
**projection of current authority, not a rival history**. For `toad > 0`, a private
Cardano-first advance is invalid because the configured witness receipts are mandatory;
there is no signature-only timeout fallback. The checkpoint can still lag a recent KERI
event. What remains is a real cross-plane
**synchronization** and **evidence** problem — witnessed KERI events must be relayed onto
the checkpoint, objective duplicity / correspondence fraud must be submitted, and
stale / false credential-status mirrors must be policed.

See [Veridian Bridge — One state machine, one stated limit](../architecture/veridian-bridge.md#one-state-machine-one-stated-limit)
and `specs/68-keystate-shape/identity-model.md` §11.

## What the super watcher is — and is not

A super watcher is a **first-class, permissionless cross-plane relayer and evidence
submitter**. It is **not** a trusted oracle, identity authority, key custodian, backup
service, recovery authority, or authoritative indexer. Ordinary KERI watchers police
**intra-KEL** duplicity for a single AID; a super watcher spans **KERI ↔ Cardano** and the
**credential-status (R-TEL) mirror**.

**It is:**
- A **permissionless cross-plane relayer and evidence submitter** — anyone can run one, no registration or trust required.
- **Precisely incentivized** — relay and freeze are permissionless but not automatically
  paid; a successful irreconcilable-fork conviction may collect the registration deposit.
- **Evidence-bound** — it only ever relays witnessed events or submits cryptographic proofs; it never adjudicates.

**It is not:**
- A trusted oracle, identity authority, or key custodian — it holds no freeze key and speaks for no one's identity.
- A backup service or recovery authority — it cannot reconstruct a lost KEL or manufacture keys.
- An authoritative indexer or resolver — locator / freshness lookups are for **liveness only, never identity truth**.

!!! note "Normative live-duty contract (#92 / NOTE-022)"
    The relayer / evidence-submitter role and the live duties below are the **normative**
    super-watcher contract (`specs/92-checkpoint-contention/spec.md` §"Loss / fork semantics
    and the superwatcher live-duty contract", NOTE-022; `specs/68-keystate-shape/identity-model.md`
    §11). What remains design-stage is the **implementation surface** — the SDK / relayer
    wiring and the submission transaction shapes — not the role itself.

## Live duties

A super watcher observes witnessed KERI events against the Cardano checkpoint and acts only
on evidence:

- **Relay a fully witnessed anchoring** transition onto the checkpoint when the seal and its threshold witness receipts are valid (the §4 / §6a two-seal handoff).
- **Submit** objective **duplicity** or seal↔native-**correspondence proofs** — the §7b fraud-proof shape, drilled via #90 — wherever the stored witness threshold receipted the divergent establishment event.
- **Request or trigger the applicable freeze** path when safe advancement is impossible: a
  later witnessed KERI event, correspondence fraud, or conflict that is not yet proved
  irreconcilable. Freezing is permissionless and is not bounty-paid by default.
- **Submit a conviction proof** only when the evidence proves two incompatible V1
  nondelegated establishment rotations from the same prior commitment, the conflicting
  event satisfies both the pre-committed controller threshold and the applicable KERI
  witness-receipt threshold, and no supported KERI superseding rule can reconcile them. A
  successful conviction pays the prover from the deposit and moves the existing token to
  its permanent tombstone.
- **Police stale or false R-TEL** credential-status mirrors, submitting evidence when a mirror misreports issuance / revocation.
- Never present post-hoc conviction as rollback: settled Cardano actions remain settled;
  mandatory advance-time receipts are what stop the Cardano-first attack.

**A super watcher never chooses truth when cryptographic evidence is absent.** Where no
threshold-receipted proof exists — for example the §7b witness-swap residual, or a
witness-threshold collusion — the super watcher can **expose and forward** the discrepancy
off-chain, but it **cannot manufacture a canonical truth branch** on-chain. It relays and
evidences; it does not adjudicate.

## Relationship to the freeze registry

The freeze registry (R-FRZ) and the super watcher serve different purposes:

| Mechanism | Authorized by | Purpose | Initiated by |
|---|---|---|---|
| Freeze registry (R-FRZ) | next_key (legitimate holder) | Emergency revocation of a stolen cur_key | Identity owner |
| Super-watcher freeze | Later witnessed event or objective non-terminal conflict | Fail closed while the controller catches up or proves a valid correction | Anyone (permissionless; no default bounty) |
| V1 conviction | Irreconcilable nondelegated rotation conflict | Stop future use and preserve a permanent audit record | Anyone (bounty-paid from deposit) |

They are complementary and both **evidence-gated**: a controller whose `cur_key` is stolen
uses the freeze registry directly; a super watcher **requests or triggers the applicable
freeze** only on an objective proof. The super watcher never holds a freeze key of its own —
it submits the evidence that authorizes the freeze path.

## Super watcher as a KERI infrastructure extension

KERI watchers already monitor KELs for duplicity — two conflicting events for the same AID
at the same sequence number. A super watcher extends this across planes:

- **Existing watcher:** observes one plane (KERI witnesses), detects **intra-KEL** duplicity.
- **Super watcher:** spans **KERI ↔ Cardano** and the R-TEL mirror, **relays** valid anchoring transitions, and **submits** cross-plane duplicity / correspondence evidence.

The implementation delta is: subscribe to Cardano checkpoint events, compare the checkpoint
against witnessed KEL state at each bound sequence number, and know how to construct and
submit the relay / fraud-proof / freeze-request transactions. Any existing KERI watcher
operator is a natural candidate to run a super watcher; because operation is permissionless
and permissionless, no coordination or governance is needed to bootstrap the fleet.

---

## Historical appendix: the retired divergence-burn design

!!! warning "Historical / superseded — retained for reference only (do not implement)"
    Everything in this appendix is the **legacy divergence-burn design**, written against the
    retired **two-independent-state-machines** premise. It is **no longer** the live role
    (see the top of this page and `specs/68-keystate-shape/identity-model.md` §11): under the
    KERI-sovereign checkpoint a witnessed Cardano-first branch is rejected at advance time.
    The old "any mismatch burns" mechanism is therefore not the live mitigation. It is
    preserved, in the past tense, only as a reference for proof mechanics; the live V1
    `Convict` path is narrower, moves the token to a tombstone, and applies only to a proved
    irreconcilable independent-AID rotation conflict.

### The retired two-registry framing

Formerly, the Cardano identity registry and the KERI KEL were described as two independently
advancing machines sharing inception material, and the super watcher was cast as a
permissionless off-chain agent that **monitored** both registries and **enforced convergence
by punishing forks**. That premise is superseded: the checkpoint is a projection of current
authority, not a second sovereign history.

### Fork = forfeit (retired)

The core invariant of the retired design was: *a controller who diverged their Cardano
identity from their KERI KEL lost their registry deposit to the first watcher that detected
it.* The deposit was framed as a convergence bond, making convergence the rational choice.
Under the sovereign checkpoint this automatic mechanism is unnecessary: a witnessed
Cardano-first branch is rejected at advance, while only a fully receipted, irreconcilable V1
rotation conflict can reach the narrower live conviction path. The old design is retained
only for the proof-mechanics history below.

```mermaid
sequenceDiagram
    participant W as Super Watcher
    participant K as KERI Witnesses
    participant C as Cardano Registry

    W->>K: (retired) Monitor KEL for trie_key's cesr_aid
    W->>C: (retired) Monitor KeyState for trie_key
    Note over W: At seq N:
    Note over W: KEL.cur_pubkey ≠ Cardano.cur_pubkey
    W->>W: (retired) Construct divergence proof
    W->>C: (retired) Submit BurnTx (trie_key, divergence_proof)
    C->>W: (retired) Deposit returned as bounty
    Note over C: trie_key entry removed from registry
```

### Burn transaction (retired)

The retired burn transaction removed a diverged identity from the Cardano registry and
transferred the deposit to the presenter.

```
BurnRedeemer {
  trie_key           : ByteArray[32]
  seq                : Int             -- sequence number where divergence occurs
  keri_event         : ByteArray       -- raw KERI rotation event at seq
  keri_receipts      : ByteArray       -- witness receipts for keri_event
  cardano_key_state  : KeyState        -- Cardano KeyState at seq
  inclusion_proof    : InclusionProof  -- trie_key → KeyState in registry
}
```

**On-chain checks (as designed, without Blake3):**
1. Inclusion proof validated `trie_key → cardano_key_state` against the current identity root.
2. `keri_event` contained a `cur_pubkey` field (extracted and presented by the watcher).
3. That `cur_pubkey ≠ cardano_key_state.cur_pubkey` at the same `seq`.
4. Ed25519 signature in `keri_event` was valid against the presented key.
5. Remove `trie_key` from the trie, return the deposit to the tx submitter.

**The [Blake3](https://github.com/BLAKE3-team/BLAKE3) gap here too:** checks 2–4 required
parsing [CESR](https://github.com/WebOfTrust/ietf-cesr) event structure and verifying
witness receipt signatures on-chain. Without Blake3 and CESR parsing builtins, the watcher
had to present the extracted fields and the script trusted the extraction — which a
malicious watcher could have forged against an innocent identity. The receipts-over-raw-bytes
fact (§5) later simplified the *correspondence* proof the live design keeps.

### Without Blake3: the trust problem (retired)

Without Blake3, the burn check was weaker: the script could not verify that the presented
`keri_event` bytes were a legitimate KERI event or that the witness receipts were genuine,
so a malicious watcher could have constructed a fake divergence proof against a controller
who had **not** forked.

**Mitigations that were considered (without Blake3):**
1. **Challenge period** — the burn was not immediate; the controller had N blocks to refute with a signed counter-proof, turning a one-sided burn into dispute resolution.
2. **Threshold watcher agreement** — N independent watchers had to present the same divergence proof before the burn executed.
3. **Governance veto** — a governance token holder could veto a burn within the challenge period.

Option 1 (challenge period) was judged the most trust-minimized.

### Deposit mechanics, economic alignment (retired)

The retired design recorded the exact ADA locked at inception as a `deposit` field in
`KeyState`; the burn script released that amount to the watcher, and larger deposits were
meant to attract more watchers. The deposit-size / watcher-incentive market was purely a
convergence-bond mechanism and does **not** apply under the sovereign checkpoint — the live
super watcher is bounty-compatible for **evidence submission**, not for burning forks.
