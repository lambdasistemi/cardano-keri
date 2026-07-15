# Decision — KERI delegation is an explicit versioned extension

Status: **DECIDED — 2026-07-15**

Issues: [#68](https://github.com/lambdasistemi/cardano-keri/issues/68),
[#81](https://github.com/lambdasistemi/cardano-keri/issues/81)

Downstream: [#24](https://github.com/lambdasistemi/cardano-keri/issues/24)
(checkpoint implementation),
[#31](https://github.com/lambdasistemi/cardano-keri/issues/31)
(historical ACDC verification)

## Decision

The first sovereign per-AID checkpoint protocol supports **independent KERI
AIDs only**.

- `CheckpointDatumV1` has **no reserved `delegator` / `di` field**.
- V1 registration accepts a non-delegated KERI inception (`icp`) and rejects a
  delegated inception (`dip`).
- V1 checkpoint advancement has no `drt`, cooperative-delegation,
  superseding-delegation, or delegated-recovery acceptance path.
- Both integer and fractionally weighted `k` / `kt` / `n` / `nt` threshold
  forms remain required. Weighted thresholds are exercised by every business
  case; KERI delegation is not.
- A later delegated-AID protocol is a **new, explicitly versioned validator and
  proof surface**. It is not activated by populating an optional byte string in
  a V1 datum.

The registration semantic-projection gate MUST attest the inception event
type. Accepting a `dip` as if it were an `icp` would silently discard the
delegator's establishment authority and is therefore invalid.

## Three different relationships called “delegation”

| Relationship | Meaning | Protocol surface |
|---|---|---|
| KERI cooperative AID delegation | A parent AID retains establishment authority over a child AID; `dip` carries immediate parent `di`, and the parent KEL anchors each delegated establishment event | Future identity-plane extension |
| ACDC authority chaining | Credentials link issuer, issuee, and role authority through SAID-addressed `e` edges and TEL status | M2 credential/admission plane |
| Cardano stake delegation | A stake credential selects an SPO | M4 identified-SPO adapter |

Only the first relationship uses KERI `di`. The three MUST NOT be presented as
interchangeable.

## Use-case evidence

| Current use case | AID that authorizes the Cardano action | Authority proof | KERI `di` in the hot path? |
|---|---|---|---|
| Regulated DeFi | trader/service OOR or ECR AID | current actor checkpoint + ACDC role/TEL admission | No |
| Identified SPO delegation | SPO Legal Entity AID plus pool cold-key attestation | LE credential/TEL + pool binding | No |
| Security tokens | holder LE AID; issuer/transfer-agent acting AID | LE/OOR credential/TEL + current acting-AID checkpoint | No |
| Institutional contracts | officer/service OOR or ECR AID | role credential/TEL + current acting-AID checkpoint | No |

These dApps use independent acting AIDs. The ACDC chain says **what role or
business authority the actor holds**; the sovereign checkpoint says **which
keys control that actor now**.

## The issuer-tier exception

Production vLEI infrastructure uses cooperative KERI delegation at the issuer
tier: the GLEIF External Delegated AID is delegated by the GLEIF Root, and a
QVI group AID is normally delegated by the GLEIF External AID. Verifying a QVI
from the GLEIF Root is therefore recursively dependent on the parent KEL.

That recursion belongs to the **historical credential/admission proof**. A QVI
does not need a current Cardano checkpoint merely because it issued a
credential in the past: issuance is verified against the historical key state
that anchored the issuance/TEL event, and later issuer rotation does not
invalidate that evidence.

M2 MUST state which root it trusts:

1. **Pinned-root V1:** pin a QVI or GLEIF External AID as the admission trust
   root and state that the omitted upstream cooperative-delegation proof is an
   explicit trust boundary; or
2. **Recursive proof extension:** verify the QVI's delegated KEL through its
   parent anchors up to the configured root.

The M2 synthetic credential-chain demo uses the first boundary unless the
second protocol has landed. It MUST NOT claim full GLEIF-Root-to-QVI KERI
delegation verification when it merely pins a downstream root.

## Why an optional `di` is rejected

`di` is one-hop data with recursively defined validity. For a child C delegated
by B, a verifier needs C's event, B's anchoring event, and proof that B is valid;
if B is delegated by A, the same obligation repeats. Storing only `di = B`
proves none of those facts.

The earlier “reserve now or never” argument depended on hashing a nullable
delegator into a frozen Cardano `trie_key`. Candidate A removed that object:
the identity handle is the qualified KERI AID, and the current state lives in
its versioned, quantity-one checkpoint-token lineage. A future datum/validator
version can add a fully specified delegation proof without pretending that an
unchecked V1 field is meaningful.

## Requirements for a future delegated-AID version

Delegated-AID support is not complete until it specifies and tests all of:

- the immediate `di` parent and exact delegated event SAID;
- the delegating-event anchor/location seal and the two-way binding;
- delegated inception and every delegated rotation;
- recursive trust-root termination, cycle rejection, and resource bounds;
- superseding/recovery, abandonment, and parent-withdrawal semantics;
- whether Cardano verifies the ancestry directly or materializes validated
  delegation-certificate UTxOs;
- transaction-size/ex-unit behavior and contention at popular delegators;
- migration between explicitly versioned checkpoint validators.

Until those conditions are met, a delegated AID fails closed at the V1
registration boundary.

## Milestone placement

- **M1 — identity core:** weighted independent-AID `CheckpointDatumV1`; #68
  freezes threshold/CBOR/message semantics; #24 implements it; #81 resolves by
  removing the passive field.
- **M2 — verification/authorization:** ACDC authority chains and TEL status;
  pin and disclose the issuer trust root. No implicit KERI delegation claim.
- **M3 — signing bridge:** unchanged.
- **M4 — pilots:** the SPO and institutional-contract actors use independent
  AIDs plus credentials; KERI delegation is not a pilot prerequisite.
- **M5 — adapters and hardening:** delegated-AID checkpoints, recursive
  delegation proofs, and delegated/superseding recovery, if demanded by a
  concrete controller-custody or production-QVI integration scenario.

