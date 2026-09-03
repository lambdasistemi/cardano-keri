# Story ladder: what has actually settled

This page is **history**. It records the transactions that reached a real
ledger, with their dates, and nothing else. What is designed but not built is
on the [home page](index.md#the-accepted-design-the-m1-return); what is
scheduled is on the [roadmap](roadmap.md).

**KERI** is Key Event Receipt Infrastructure, the off-chain protocol that
maintains an identity's signed key history. A KERI **AID** (Autonomic
Identifier) names the identity, and its **KEL** (Key Event Log) contains the
inception and rotation events for that AID. cardano-keri projects the current
KERI key state into a Cardano **checkpoint UTxO**: an unspent transaction
output that carries one identity-specific token and an inline datum with the
current keys, thresholds, witnesses, and sequence number.

!!! note "What “settled” means"
    The transaction reached a real ledger — either a private protocol-11
    development network configured with Cardano's production transaction
    limits, or Cardano preprod. This is stronger evidence than an emulator or
    a unit test. It is **not** a mainnet deployment or a production-readiness
    claim.

!!! warning "The machine these stories exercised is being replaced"
    The devnet ladder below settled the ACTIVE/ARMED/FROZEN enforcement
    economy — freeze for lag, the claimed delay bond, the burn-only
    conviction. The M1 return removes that economy: the freeze becomes a
    hunter's payment when the owner's pool has run dry, and conviction becomes
    a terminal state reached only by a proven duplicity. These rungs are kept
    as the record of what the vertical path proved, not as a description of
    where the design is going. Epic
    [K1](https://github.com/lambdasistemi/cardano-keri/issues/319) removes the
    code they exercised.

---

## On preprod — 2026-08-06

The M1 V1 programs were published on preprod on **2026-07-28** from source
commit `50a5820` (five reference scripts, registration bond 1,000 tADA, freeze
bond 5 tADA, freeze window 10,000 slots). See
[the M1 preprod deployment](user/m1-preprod-deployment.md).

A genuine KLI identity then completed the register → advance → close journey
through the packaged `ckeri`, in process, on **2026-08-06**:

| Step | AID | Transaction | Capture |
|---|---|---|---|
| BLAKE3 premint | `EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P` | `167220b32479b2ae91eb4e754460b71bf51d44b331660ab31cf4e2264fb30b68` | `deploy/preprod/m1-register-acceptance.txt` |
| Register | same | `6ecc2e0729347f5008a4f07ba18c2ce6ad745ace4911818b838037dfc83241e2` | `deploy/preprod/m1-register-acceptance.txt` |
| Advance | same | `f0f3a18ff994f5865b638dab33e166b8baa9996eb58d1691f0d26c8b218bfe4a` | `deploy/preprod/m1-advance-acceptance.txt` |
| Close | same | `446f0d831ee69aa067516ec6cb6d696a8dee64bf7be00694030cfe061de9010f` | `deploy/preprod/m1-close-acceptance.txt` |

Separate historical-negative captures record the failures that must also hold
against the deployed programs: an already-registered AID, an ambiguous
checkpoint set, an unlisted witness, and — for advance — under-signed,
under-witnessed and stale attempts, each reaching the deployed Plutus
evaluator and failing there.

No enforcement transaction has ever settled on preprod. `ckeri` exposes no
freeze, claim or convict command; those paths exist only in the end-to-end
harness.

---

## On the protocol-11 development network — 2026-07-27 and 2026-07-28

The fixture has two controller keys and genuine `keripy`-produced events and
witness receipts. `keripy` is the reference KERI implementation used to produce
and verify the test history.

| Date | Rung | What settled | Record |
|---|---|---|---|
| 2026-07-27 | Register small | BLAKE3 premint and a bonded ACTIVE checkpoint | [PR #146](https://github.com/lambdasistemi/cardano-keri/pull/146) |
| 2026-07-27 | Close small | Controller-authorized burn and full refund | [PR #147](https://github.com/lambdasistemi/cardano-keri/pull/147) |
| 2026-07-27 | Rotate small | A genuine witnessed Advance | [PR #148](https://github.com/lambdasistemi/cardano-keri/pull/148) |
| 2026-07-27 | Freeze and respond | Freeze, response, stale-replay rejection, and a fresh second round | [PR #150](https://github.com/lambdasistemi/cardano-keri/pull/150) |
| 2026-07-28 | Seize the delay bond | An unanswered deadline paying the recorded hunter, then thaw by an Advance re-posting `B` | [PR #154](https://github.com/lambdasistemi/cardano-keri/pull/154) |
| 2026-07-28 | Convict a fork | A fully witnessed irreconcilable conflict, protected payouts, token burned, no successor | [PR #155](https://github.com/lambdasistemi/cardano-keri/pull/155) |

Together these establish a vertical path through the production validators,
the transaction builder, node submission, and the settlement boundary.

### Register — PR #146

The expensive BLAKE3 calculation ran first and minted a short-lived proof
token. Registration then consumed that fact, created the checkpoint, and
locked the two bonds.

| Transaction | Txid |
|---|---|
| BLAKE3 premint | `7222d36ea5f3791877cf8ca779a76d6241cf16a709c8908a058d6ca791b1526b` |
| Register | `84118d89a5c0c57e35a1af9666cd266a7e70818600dbe9499819f69efcb20e90` |

### Close — PR #147

The story registered the same small identity, then its current controllers
authorized a refund to output zero.

| Transaction | Txid |
|---|---|
| Register | `84118d89a5c0c57e35a1af9666cd266a7e70818600dbe9499819f69efcb20e90` |
| Close | `1d8afdf5b9f87ee32c10cb96d4fc82a8e6c23a9d1212074ba2dcd244ebde91b1` |

### Rotate — PR #148

The Advance transaction consumed the registered checkpoint and created its
single successor. The same live run also settled a Close regression.

| Transaction | Txid |
|---|---|
| Advance | `04c3673798c9e555ad1cd0cf32efb9a9265d75ef0b464502eb5bfd8e8bd0b055` |
| Close regression | `7008cd9c93b5c5c252af61b2734831f3ac7f532e95eebd4bf988ecaf7ae50fc7` |

### Freeze, response, and replay rejection — PR #150

This is a two-round security drill, not two copies of a unit test. After the
first response advanced the checkpoint, the runner replayed the exact old
Freeze evidence. The applied checkpoint and enforcement observer rejected it
before submission. A fresh pair of conflicting rotations at the next KERI
sequence then opened and resolved a second challenge normally.

| Step | Txid |
|---|---|
| Register | `c4b315a43c72b8493284c0e30b1dd90bf354e96f35d6f9b90f7f4c21c632e71e` |
| Recorded rotation | `1b4acf5b3f62c09a5627aeac364d798728a375bd3340d7e19bba4765e8c60532` |
| First hunter Freeze | `08cc097782780f02d5a69dba763566d62d74e0e763816c1e3eb3e4155ff501e7` |
| First honest response Advance | `1503db7294bf3ffef24ef44c424714024f2d1784788be4fd730427c91aedde60` |
| Fresh second Freeze | `bc96940734bb3b3866b215ad189bd9a2a8b8c4f4282410b5c836631d9fedd9ec` |
| Second honest response Advance | `6b706faf955a303cd5bb425440595ab729a4e4438948e2f3009080e039f24b3c` |

Both responses preserved the checkpoint's complete value, including the delay
bond. The old evidence failed because it no longer described a rotation ahead
of the new tip. That binding — evidence to the exact state it challenges — is
the part of the drill that survives the M1 return: the freeze of the new design
also runs the advance predicate on the rotation it presents.

The transaction IDs for the seize and convict rungs are in the merged records
of [PR #154](https://github.com/lambdasistemi/cardano-keri/pull/154) and
[PR #155](https://github.com/lambdasistemi/cardano-keri/pull/155).

---

## What the ladder did not reach

- **GLEIF scale.** The settled fixtures are two-key and 1-of-1. The genuine
  three-of-seven shape with a real witness set has never completed the vertical
  ladder, and the cost of doing so is what epic
  [K3](https://github.com/lambdasistemi/cardano-keri/issues/321) exists to
  measure.
- **The engineering ceiling.** `observer-advance` measures 16,130 bytes against
  a 16,133-byte limit. Every rung above was settled inside three bytes of
  headroom.
- **Enforcement on a public network.** Freeze, claim and convict settled on the
  development network only, and never through `ckeri`.
- **Uniqueness.** Nothing in the ladder prevents two checkpoints for one AID.
  The ledger has no AID-unicity rule today; `ckeri register` refuses an
  already-live AID as a convenience, not as a guarantee. The registry of the M1
  return is what turns that into a rule.

## Where to read next

- [The M1 preprod deployment](user/m1-preprod-deployment.md) — the published
  release, its manifest, and how to verify it.
- [Observer architecture](architecture/observer-architecture.md) — the thin
  checkpoint, reference scripts, zero-lovelace withdrawal, and BLAKE3 fact
  token, with measured sizes and costs.
- [Identity operations](architecture/identity-ops.md) — the operation-by-
  operation view of what ships and what replaces it.
