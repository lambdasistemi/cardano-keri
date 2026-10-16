# Preprod checkpoint inventory

US-279: As the cutover owner, I need a reproducible inventory of the currently live deployed checkpoint set and proof that the instrument detects non-ACTIVE states.

All invariants are BLOCKING for any cutover-clear claim.
- INV-279-EXTENT: enumerate every live checkpoint role and all policy assets, with explicit pagination termination, duplicate detection, and reconciliation. Never treat a partial/failed query as empty. Distinguish UTxOs, unique identities, and historic burned identities.
- INV-279-ROLE: classify full addresses from the deployed policy and deterministic role staking credentials; ACTIVE, ARMED, FROZEN, TOMBSTONE, and UNKNOWN are distinct.
- INV-279-DECODE: decode raw inline CBOR with exact version/arity/types, ArmedV1 and ArmedV2, checkpoint and tombstone shapes; malformed, missing, unknown and inconsistent datums remain counted failures.
- INV-279-CONTROL: the same report path detects synthetic positive ARMED V1/V2 and FROZEN; malformed/unknown rows and truncated enumeration prevent a clear verdict. Record what each control proves and its live-query limits.
- INV-279-REPORT: name each output, AID, asset, address, locked value, state, and non-ACTIVE deadline/resolution actor or explicit absence of a path; counts reconcile with examined, decoded, failed and unknown denominators.
- INV-279-PROVENANCE: capture time, preprod tip, endpoint, public requests/responses, manifest identity, page evidence and hashes. Verify live deployed script references. Report drift and stale/moving snapshot limits. Repeat immediately before cutover.
- INV-279-READONLY: public chain reads only, no credentials, signing, transaction submission, configuration discovery, or script changes.

A zero ARMED/FROZEN count alone is never cutover authorization. Unresolved enumeration/decode/provenance errors withhold a complete verdict. A nonzero count escalates to M1 immediately.
