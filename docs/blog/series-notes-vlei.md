# Series notes — future installment: "Who gets to be Coca-Cola?" (the verification core, M2)

Reserved material (do not use in post #1). Core arc:

1. **The name is attested, never asserted** — GLEIF → QVI → LE credential chain; the LE vLEI names the AID as subject and carries the LEI; officers via OOR/ECR. M2 verifier: schema pins, historical key state at issuance (KEL replay), hop-bounded edges, cascade non-revocation via TELs (on-chain per-issuer mirror from M1).
2. **Impostors hold nothing** — a fresh AID can register (by design) but cannot produce an LE credential with Coca-Cola's LEI; forgery = corrupting a QVI = accreditation-hard and cascade-revocable (revoking the QVI's own credential invalidates its issuance history for verifiers).
3. **Admission vs enforcement** — verify the chain off-chain once at admission, record the AID; every transaction thereafter enforces only the checkpoint (current keys/threshold, atomic).
4. **Two nested lifelines** — pre-rotation recovers from key *theft* without touching credentials; revoke-and-reissue (LEI is the durable identity, AID is replaceable) recovers from key *annihilation* without touching the legal identity. Ties back to post #1's "total key loss is total loss" limit: the credential layer is the escape hatch above it.
5. One-liner: to act as Coca-Cola you need their pre-committed keys (theft-hard) or a fraudulent QVI issuance (accreditation-hard, revocable) — checked independently, at admission and at every transaction.
