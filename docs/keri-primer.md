# What is KERI, and what does Cardano add?

This is the recommended starting point for understanding `cardano-aid`. It covers what KERI is, how it works, what Veridian is, and what Cardano brings to the picture.

---

## The problem KERI solves

Digital identity today relies on trusted intermediaries: certificate authorities issue your TLS certificate, domain registrars control your domain, platforms control your username. If any of them revoke your credentials — or get hacked — your identity is gone or compromised.

[KERI](https://github.com/WebOfTrust/ietf-keri) (Key Event Receipt Infrastructure) removes the intermediary. Your identity is derived directly from your cryptographic key material. No issuer, no registrar, no permission required.

But there is a harder problem underneath: **what happens when your key is compromised?** In traditional PKI you call the CA and get a new certificate. In a self-certifying system there is no CA to call. KERI's answer is pre-rotation.

---

## Pre-rotation: the core mechanism

At inception you commit to two things simultaneously:

```
cur_pubkey  — the key you will use right now
next_digest — hash(next_pubkey), where next_pubkey stays secret
```

The `next_digest` is a binding commitment to your next key, made before anyone — including an attacker — knows what that key is.

When you rotate, you **reveal** `next_pubkey` (proving you knew it all along) and simultaneously commit to the key after that:

```
rotation:
  reveal_key  — the next_pubkey you committed to at inception
  new_next    — hash(new_next_pubkey), the next commitment
```

**A thief who steals your current key cannot rotate your identity.** They do not know `next_pubkey` — only its hash is public. Pre-image resistance on the hash function is the security assumption.

This means key theft is recoverable: you rotate before the attacker can, revoking the stolen key and installing a new one, all without any third party.

---

## The Key Event Log (KEL)

Every key event — inception, rotation, interaction — is appended to the Key Event Log. It is an append-only, hash-chained log of everything that has ever happened to a KERI identity.

```
inception  →  rotation  →  rotation  →  interaction
[seq=0]       [seq=1]       [seq=2]       [seq=3]
  │              │              │
  └──hash────────┘              │
                 └──hash────────┘
```

Each event references the hash of the previous event. The log is tamper-evident: you cannot alter an earlier event without breaking every subsequent hash. The KEL is the full proof of an identity's history, self-contained and verifiable by anyone.

---

## The AID: a self-certifying identifier

The AID (Autonomic Identifier) is derived as:

```
AID = blake3(inception_event)
```

It is self-certifying: the identifier itself encodes the cryptographic proof of who controls it. No third party issued it. No registry assigned it. You present the inception event and anyone can verify the AID is correct.

!!! note "Digest agility"
    KERI supports digest agility; Blake3 (`E` prefix) is Veridian's chosen algorithm. Other KERI implementations may use different hash functions.

In Veridian and KERI generally, AIDs are encoded in [CESR](https://github.com/WebOfTrust/ietf-cesr) format — a compact Base64-based encoding that encodes the hash algorithm alongside the value.

---

## Witnesses: solving duplicity

The KEL alone has one remaining vulnerability: you could broadcast two conflicting events at the same sequence number to different parties — "I rotated to key A" to Alice, "I rotated to key B" to Bob. This is called **duplicity**.

KERI solves duplicity with witnesses. At inception you declare a witness set and a threshold:

```
inception:
  witnesses: [W1, W2, W3]
  threshold: 2-of-3
```

Every event must be receipted by at least 2 of your 3 witnesses before it is valid. Witnesses:

- Receive your events
- Refuse to receipt a conflicting event at a sequence number they've already receipted
- Return signed receipts
- Host your KEL publicly

As long as fewer than the threshold collude, duplicity is impossible — no witness will sign a conflicting event.

---

## Watchers: independent verification

Verifiers (parties relying on your identity) run **watchers** — independent monitors that observe the witness pool and look for duplicity across your entire KEL history. If your witnesses collude and try to show different KELs to different parties, watchers detect it.

```
You (Veridian / Signify)        ← key custodian, sole signer
     ↓ signs events
KERIA (your cloud agent)        ← network relay, KEL storage, no keys
     ↓ submits to witnesses
Witnesses (threshold quorum)    ← receipt providers, duplicity detection
     ↓ signed receipts + KEL hosting
Watchers (run by verifiers)     ← independent duplicity monitoring
     ↓
Verifier trusts the result
```

---

## Veridian: signing at the edge

Veridian is a consumer KERI wallet built on [Signify](https://github.com/WebOfTrust/signify-ts) (TypeScript). Its defining principle: **private keys never leave the device**. 

The [KERIA](https://github.com/WebOfTrust/keria) server handles networking, KEL storage, and witness interaction — but it cannot sign anything. It has no keys. Veridian is the sole signing oracle. A compromised server cannot forge events on your behalf.

This makes Veridian suitable for real-world identity use cases — [GLEIF vLEI](https://www.gleif.org/en/organizational-identity/introducing-the-verifiable-lei-vlei) credentials, legal entity identifiers, verifiable credentials — where key custody must stay with the controller.

---

## What KERI is good for

**No infrastructure lock-in.** Your AID is not tied to any domain, CA, or company. Migrate witnesses, change your agent, and your identity stays the same.

**Recoverable key compromise.** Stolen key → rotate → same identity, new key. No reissuing certificates, no notifying every relying party.

**Portable verifiable history.** Present your KEL to anyone; they verify your complete key history without trusting any intermediary. Self-contained proof.

**Threshold multi-signature.** N-of-M keys required for any event. Natural for organisations, DAOs, legal entities.

**Delegation.** Delegated AIDs let an organisation vouch for sub-identities ([vLEI](https://www.gleif.org/en/organizational-identity/introducing-the-verifiable-lei-vlei) pattern: GLEIF → QVI → Legal Entity → department).

---

## Where Cardano fits

KERI solves identity portability and key rotation. It does not solve:

| Gap | Cardano adds |
|---|---|
| Approximate event ordering (witness timestamps) | Exact global slot ordering |
| Duplicity detection (watchers after the fact) | Duplicity prevention (UTxO spent once, structurally impossible) |
| No composability with contracts | Smart contract integration, DeFi, governance |
| Off-chain only | On-chain data anchoring via MPFS value cages |

The `cardano-aid` bridge reuses the same Ed25519 keys Veridian already manages. No re-keying. The same signing operation that advances the KERI KEL also advances the Cardano registry. Cardano becomes an additional witness — one with stronger ordering and composability guarantees than any witness pool.

## The Blake3 frontier

**Near-term path (no hard fork):** if Veridian adds F-prefix (Blake2b-256) support for new AID creation — a ~40-line change to `prefixer.ts` — new identities are fully Cardano-verifiable today. See the [proof-of-concept CLI](https://github.com/lambdasistemi/cardano-keri-verify) and the [Veridian fix branch](https://github.com/lambdasistemi/signify-ts/tree/feat/blake2b-256-prefix-derivation).

Veridian AIDs are derived as `blake3(inception_event)` — this is Veridian's implementation choice, not a KERI protocol requirement. KERI's CESR encoding supports digest agility; the `E` prefix denotes Blake3, but other prefixes (e.g. `F` for Blake2b-256) are equally valid KERI. Plutus currently has no Blake3 builtin, so the on-chain script cannot verify that a presented AID is the correct Veridian identifier for a given key. This means:

- Two Veridian users who already know each other's AID via KERI: **fully verifiable** — replay the KEL, derive the Cardano identity
- A Cardano-only application trying to resolve a KERI identity without touching the KERI network: **cannot trust the AID field** until Blake3 lands in Plutus

With Blake3 as a Plutus builtin, Cardano could verify KERI AIDs natively — closing the squatting gap entirely. The next-key commitment chain is already Cardano-verifiable today via Blake2b-256 digest agility (KERI supports multiple hash algorithms). Full on-chain AID verification — one submission, no sync lag, Cardano block inclusion replacing the witness receipt — requires Blake3. For Cardano-anchored AIDs, the traditional KERI witness infrastructure becomes optional.

See [Blake3 requirement](design/blake3-requirement.md) for the full analysis and the ZK proof interim path.

---

*Next: [Architecture overview](architecture/overview.md) | [Veridian bridge](architecture/veridian-bridge.md) | [Identity operations](architecture/identity-ops.md)*
