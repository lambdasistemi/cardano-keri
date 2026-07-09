# The vLEI/ACDC zoo — real facts for #68

Assembled from the live vLEI schemas (`WebOfTrust/vLEI`), GLEIF-IT operational
configs (`GLEIF-IT/vlei-qvi`, `GLEIF-IT/gar`), the GLEIF vLEI EGF, and the KERI
spec. Purpose: decide the frozen KeyState shape (#68) from evidence.

## A. The credential chain is ACDC edges, not KERI delegation

The 7 vLEI ACDC schemas and how they chain (issuer → issuee, via the `e` edge block):

| Credential | Edges? | Chains to (parent) | Edge operator |
|---|---|---|---|
| QVI | no | — (top; issued by GLEIF) | — |
| Legal Entity (LE) | yes | QVI credential | (none) |
| OOR-AUTH | yes | LE credential | (none) |
| OOR | yes | OOR-AUTH credential | `I2I` |
| ECR-AUTH | yes | LE credential | (none) |
| ECR | yes | LE **or** ECR-AUTH | `I2I` on the AUTH path |

```
GLEIF ─▶ QVI ─▶ LE ─┬─▶ OOR-AUTH ─▶ OOR     (OOR path: 4 hops)
                    ├─▶ ECR-AUTH ─▶ ECR     (ECR authorized: 4 hops)
                    └──────────────▶ ECR     (ECR direct, LE-issued: 3 hops)
```

**Fact 1.** Chaining is credential-to-credential via ACDC `e` edges pinned by
schema-SAID; authority is asserted with the ACDC edge operator `I2I`. **No schema
contains any KERI delegation field** (`dip`, `drt`, `delegator`, `di`). → The
trust chain is a **Layer-3 verifier** concern (#31/#32), *not* an identity-plane
concern. Confirms hop-bound = 4 (OOR/ECR-AUTH), 3 (ECR direct).

## B. Thresholds: weighted fractions are MANDATED and used in production

Real GLEIF-IT inception configs (quoted):

- QVI group AID (`GLEIF-IT/vlei-qvi/scripts/aid-incept.json`):
  `"isith": ["1/2","1/2"]`, `"nsith": ["1/2","1/2"]`
- GLEIF External/GAR group AID (`GLEIF-IT/gar/external/scripts/ext-aid-incept.json`):
  `"isith": ["1/2","1/2"]`, `"nsith": ["1/2","1/2"]`
- Single-sig/local AIDs use the integer form: `"isith": "1"`.
- `kli multisig incept` prompts **per-participant, non-uniform** weights
  (a `1/5` example) — not expressible as integer m-of-n.

GLEIF docs (quoted): *"The vLEI EGF … mandates that the GLEIF AIDs all use
fractionally weighted thresholds … an event is not valid until … the sum of their
fractional thresholds equals at least 1."* Same for QVI AIDs.

**Fact 2.** KERI encodes `kt`/`nt` as **either** a hex-int string (`"2"`) **or** a
list of rational-fraction weights (`["1/2","1/2"]`), valid when the signed subset's
weights sum to ≥ 1. Real vLEI issuer/GLEIF AIDs use the **fraction** form. → An
integer-only KeyState would **reject production GLEIF/QVI AIDs**. We must support
both forms, including non-uniform weights.

## C. Delegation: only issuer-tier AIDs are delegated

| AID type | Delegated? | Registers on a Cardano registry? |
|---|---|---|
| GLEIF Root | independent (root of trust) | no (GLEIF-internal) |
| GEDA / GIDA (GLEIF ext/int) | **delegated** by Root | no (GLEIF-internal) |
| **QVI AID** | **delegated** by GEDA | maybe (issuer tier) |
| **Legal Entity AID** | independent (holds LE credential) | **yes — common** |
| **OOR / ECR individual** | independent (holds role credential) | **yes — common** |
| SPO / counterparty | independent (not vLEI) | **yes — common** |

**Fact 3.** A delegated AID (`dip` inception) carries a mandatory `di` = delegator
AID; its identity is **inseparable from its delegator**. But of the AIDs that would
register on a Cardano registry, **only QVI-tier AIDs are delegated** — the dominant
registrants (LE, individuals, SPOs) are all **independent**. Delegation is the
exception, not the common case.

## What the facts decide

- **D-D — weighted thresholds: REQUIRED (was leaning wrong).** Support both the
  integer and the fractional-weight-list form for the current and next threshold.
  Consequence: on-chain rational-weight arithmetic + a well-formedness predicate
  (finding F18), and the pre-rotation proof must cover the *next threshold*, not
  just the next keys.
- **D-E — `delegator`: reserve nullable, don't privilege it.** `null` for the
  dominant independent case; populated only for a delegated (QVI-tier) AID, whose
  identity KERI binds to its delegator. Frozen-forever + cheap (one nullable slot)
  ⇒ reserving the option is the conservative call; full delegated-inception
  verification is deferred (like the credential verifier), the field just holds the
  binding.

## Sources
- https://github.com/WebOfTrust/vLEI/tree/main/schema/acdc
- https://github.com/GLEIF-IT/vlei-qvi/blob/main/scripts/aid-incept.json
- https://github.com/GLEIF-IT/gar/blob/main/docs/creating-group-aid.md
- https://www.gleif.org/en/organizational-identity/become-a-vlei-issuer-qvi/vlei-ecosystem-governance-framework
- https://www.vlei.wiki/concept/nested-cooperative-delegated-identifiers
- https://trustoverip.github.io/kswg-keri-specification/
