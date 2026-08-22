# cardano-keri project ledger

## Project definition

`cardano-keri` is the product line for projecting KERI control-state evidence
onto Cardano and making that projected state consumable by Cardano scripts and
applications. It remains an architectural experiment until its named gates and
external product gate pass. No mainnet, production rollout, announcement, or
external commitment follows from an experiment result.

## Ordered milestone map

| Product milestone | GitHub milestone | Lifecycle | Outcome / current state | Owner and runtime |
|---|---:|---|---|---|
| M1 — identity core feasibility | 1 | CUSTODIAL-TERMINAL | Both commissioned evidence artifacts delivered. INV-BIND repair retained as proven; G1 budget evidence retained with caveats; monolithic `checkpoint.checkpoint` ruled NO-GO at 25,934 B. Nothing reopens here. | `%5511`, session `keri`, `/tmp/ms-keri-1` |
| M1.2 — decomposed record+cursor family | 11 | ACTIVE | S0 and S1 are in fresh audit/repair loops. All 15 residual M1 issues have product rulings accepted: 7 ADOPT, 8 REWRITE, 0 CLOSE. Exact issue payloads are being authored locally; no issue mutation is active. Conditional release `c6a88a47…` prepares S2, decoder-mainline landing, and manifest-bound issue bookkeeping, each behind its named barrier. | `%6695`, session `keri-m12`, `/tmp/ms-keri-11` |
| M8 — Plutus Blaster | 8 | PARKED | Preserved under OMNIA PAUSA. This founding does not release, restart, or modify it. | `%5331`, session `keri-ms8-blaster`, `/tmp/ms-keri-8` |

M7/M1bis delegation and credential state is a named future boundary, not an
ACTIVE milestone founded by this ledger entry.

## Project priority

1. **M1.2 S0/S1 acceptance:** finish the fresh audits. S0's current seven
   per-script rows are individually green after redesign, with three large
   members at roughly 52–54%; S1 repaired six submission-1 findings and is in
   a fresh audit. Neither is accepted merely because a repair exists.
2. **M1 backlog steering, now and non-realizing:** classifications are accepted
   at 7 ADOPT / 8 REWRITE / 0 CLOSE. Finish the exact complete mutation
   payload, validate it against fresh live issue versions, and obtain separate
   project acceptance before any issue mutation.
3. **M1.2 S2 and decoder mainline:** conditional release is already in hand,
   but self-executes only after the milestone owner accepts both S0/S1 and the
   project owner independently verifies the evidence and records
   `M12-S2-ACTIVATED`.
4. **S2 first question:** prove the new TxB witness mode, measure the pinned
   `maxRefScriptSizePerTx` and reference-script fee tiers at 25,617 B, and
   preserve/test the inline branch. The 158% resemblance to M1 is not a NO-GO.
5. **M1.2 S3:** withheld at the preprod boundary; a later written machine
   release must name what the drill writes.
6. **M8:** remains parked; new conflicting cardano-keri capacity goes to M1.2
   under the operator's 2026-08-18 “build the redesign now” instruction.

## Cross-milestone inheritances

- M1 terminal steering package sha256
  `793bab01059d18bd8f9bd20fd9ec3e37b7454b06ea7bb20f87ec1b9ea3d56410`.
- G0: unchanged pre-repair gate `7037228…` proves the decoder repair in both
  directions. The missing aggregate marker is a harness failure, not a subject
  failure; no fifth M1 slot.
- G1: terminal result sha256
  `57585ae0c92d716b93b98c11addc16ee440bca9feca7f4b177b3f31423e85160`;
  its intervals, extrapolations, blocked historical terminal, and 1/4
  respelling caveat remain attached.
- The central monolithic checkpoint is not an M1.2 implementation candidate.
- M1.2 inherits the product-gate scouting result and its PRAGMA-coupling
  caveat, but the product gate remains outside milestone 11.

## Current blockers and next transition

- The complete 15-row backlog triage is accepted at the ruling level, sha256
  `6097aa95…`. Surface C is still blocked: the prose manifest is not an exact
  API payload. A deterministic 15-entry artifact with complete final bodies,
  titles, target milestone/state/comments and fresh concurrency bases is being
  authored locally and requires separate project acceptance.
- Product decision for `#279`: any eventual cutover targets record+cursor, but
  no preprod action follows; S3/G2 remains separately withheld.
- S0 and S1 audit acceptance is open. A and B of conditional release
  `c6a88a47…` remain prepared/inactive until the two-party activation record.
- Issue mutations remain behind exact-payload acceptance. The machine's
  manifest-bound grant is not blanket authority.
- Product release, S3/preprod, mainnet, announcement, delegation/credentials,
  product-gate work, claims, and any M1 restart remain withheld.
