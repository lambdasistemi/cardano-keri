# Milestone 8 ledger — Blaster compiled UPLC verification

Updated: 2026-08-02T20:19Z

## Observable outcome test

From a fresh checkout, run the exact repository CI command and demonstrate that the pinned Aiken build's production blueprint is completely reconciled, the selected P0 security properties execute against the exact compiled Plutus V3 UPLC, source-level negative controls make the instrument fail, clean artifact hashes are restored, and the audit report accurately distinguishes SMT-valid results without proof terms from kernel proofs, tests, unproved claims, and out-of-scope claims.

## State

| Priority | Unit | GitHub | State | Owner/window | Dependency |
|---:|---|---|---|---|---|
| 1 | Blaster bridge | #189 | 🟡 active — #192 PR #215, S1 accepted/pushed at `f2d8e0b`; S2 real import/purpose/preparation starting | epic owner `%5236`; child #192 owner `%5241`; preserved PAIR `%5279`/`%5280`; #193–#195 undispatched | M1 dependency dissolved; S2 preserves the accepted S1 base and root-file fence |
| 2 (parallel) | Root-gate lifecycle migration | M8 work item; issue/lane TBD | ⏳ ready to commission, non-blocking for #192 | M8 milestone desk until a standalone owner is commissioned | Operator assigned M8 ownership; preserve #192's root-file fence |
| 3 | Compiled-contract theorem portfolio | #190 | ⏳ queued/inventory may start | epic owner not yet dispatched | P0 ratification waits for #189 tractability gate; properties wait for frozen bridge |
| 4 | Independent milestone acceptance | milestone #8 | ⏳ queued | milestone owner | #189 and #190 accepted; root-gate contract disposition explicit |

## Priority order and reasons

1. #189 first because theorem count has no meaning until extraction, preparation, trust, builtin support, tractability, and negative controls are measurable.
2. The M8-owned root-gate migration is commissioned in a separate standalone lane as capacity permits. It must not block or leak into #192; #192 keeps `gate.sh` and `.gitignore` forbidden and uses its frozen runtime gate.
3. #190 may inventory in parallel, but the operator cannot ratify P0 until #189's tractability record exists and no property is accepted outside #189's frozen artifact contract.
4. Milestone acceptance is a fresh-checkout outcome audit, not a count of closed epics.

## Active rulings and next decisions

- Operator ruling `2026-08-02`: `legacy-root-gate-migration` belongs to M8, while #192 is free to test Aiken without M1. The M1 dependency is dissolved rather than satisfied, and the migration is parallel/non-blocking. #192 may not edit the shared root `gate.sh` or `.gitignore`.
- #192 S1 is accepted and pushed on draft PR #215 at exact local/remote/PR head `f2d8e0b22c7f431e44d245833558efc443806f95`. Corrected RED, seeded real-Nix negative, exact restoration, restored positive, navigator GREEN/commit review, source identity, fresh focused gate, and fresh full `just ci` acceptance gate passed. Twelve tasks are closed and 18 S2/S3/final-acceptance tasks remain. S2 was durably dispatched through the existing epic and ticket-owner chain for real production import, purpose handling, and Plutus V3 preparation; existing worker contexts are preserved. Whole-ticket acceptance remains withheld.
- `OMNIA-PAUSA-2026-08-02` was lifted by the post-reclaim and Blaster-urgent releases. The exact chain resumed in place; no worker was recreated or replanned. Only foreground supervision, the resource guard, the held negative/restoration/positive sequence, and navigator review were re-armed; wake sources re-armed: 0. Standing guards remain 30 GiB free on `/`, 8 GiB maximum per-command consumption, and stable post-exit readings, with `/run` treated as tighter.
- Root-gate migration commissioning: create a separate M8 standalone ticket/lane; require positive and negative lifecycle controls plus normal CI. It is a contract-hardening item, not a prerequisite for #192.
- P0 proof-form scope: blocked on #189 tractability result; operator ratifies supported theorems and consequence-bearing waivers.
- Deployment binding: decide whether deployed parameter values/applied-script hashes are in scope; otherwise publish `OUT-OF-SCOPE` explicitly.
- Lifecycle baseline: choose deliberately at P0 ratification to avoid duplicated work around expected burn-axiom validator changes.
- Bridge location, current Lean CI pin scope, and total CI wall-clock budget: #189 must close these before freezing its artifact contract.
- Due date: unset by operator; do not invent one.

## Founding evidence

- Authoritative contract: `/tmp/ms-keri-1/bootstrap-blaster/brief.md`, SHA-256 `9470273374e88d1a86a6bb428de58a59622f21dbf01d3f9694d975e5e8f5b6a7` on the founding host.
- Fable pass 1: SHA-256 `7607cf4fe930d8441cc91908ef213c66524936188a8b3ea12b30f78db9800f97`.
- Fable pass 2: SHA-256 `efab1388e2e5e80d8d65d8e3d75636f7e9b544ff8086d3ab9b7016b555f0b7e5`.
- Final reconciliation: SHA-256 `9c17b35a3743521aa28a5eb08a864855c3ee14b8b97c7fcdc9cb03f696e6bfc0`.
- Reference only: cardano-foundation/cardano-mpfs-onchain PR #51; never attach it to this milestone.
