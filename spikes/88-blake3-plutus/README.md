# Spike #88 — in-script blake3 via Plutus V3 bitwise builtins

Question: can `blake3(icp_bytes) == cesr_aid_prefix` be verified inside a
Plutus V3 validator within per-tx execution budget, for KERI inception events
up to 1024 bytes (single blake3 chunk)?

Context: `specs/68-keystate-shape/identity-model.md` §7a / open thread 3.
Genesis is once per identity, in its own registration tx — not hot-path.

Deliverables (see issue #88):
1. blake3 (single-chunk, ≤1024 B) in Aiken using the Plutus V3 bitwise builtins
2. correctness vs official BLAKE3 test vectors
3. ex-units measurements vs mainnet per-tx budget → REPORT.md with the verdict
