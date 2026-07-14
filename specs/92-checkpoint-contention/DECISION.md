# DECISION — #92 R-KEL checkpoint storage: the sovereign per-AID checkpoint UTxO (Candidate A)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/92
Parent epic: https://github.com/lambdasistemi/cardano-keri/issues/21
PR: https://github.com/lambdasistemi/cardano-keri/pull/104

This record states the **decision** for open thread 8 of
`specs/68-keystate-shape/identity-model.md` — the physical storage / contention model
for the identity R-KEL checkpoint advance path. The decision was **made by the
operator** (`answers/A-001-thresholds.md`, ratified 2026-07-14) as a normative
security / product architecture. It is **not** the outcome of a throughput / capital /
cost measurement contest, and it does **not** depend on ratifying B/C measurement
thresholds. See `spec.md` (§Operator decision, NOTE-021) for the full framing.

## Machine headers (parsed by `accept.sh`)

```
SELECTED_CANDIDATE = A
REJECTED_CANDIDATES = B,C
SELECTION_BASIS = sovereignty — the operator-ratified unrelated-AID isolation invariant
SELECTION_RULE = select the shape under which each AID's current-authority state advances only through its own uniquely-tokenized UTxO, so unrelated and hostile AIDs cannot contend with, consume, serialize, or delay it; this is a normative sovereignty decision, not a measured throughput/capital/cost comparison
OPERATOR_RATIFIED = answers/A-001-thresholds.md (operator-ratified 2026-07-14; supersedes the QUESTION-001 measurement hard-stop)
SOVEREIGNTY_INVARIANT = unrelated issuers and attacker-created AIDs cannot contend with, consume, serialize, or delay an AID's current-authority checkpoint / rotation / recovery / re-authorization path, because each AID advances only through its own uniquely-tokenized (checkpoint_policy_id, aid_asset_name) UTxO
B_REJECTION = a single/global/shared MPFS checkpoint-root UTxO serializes unrelated identities on one contended UTxO, so one AID's liveness depends on every other AID's write cadence
C_REJECTION = a public/grindable lane f(cesr_aid) lets hostile AIDs target a victim's lane, and makes an AID's sovereignty depend on shard machinery (K, f, re-shard migration) rather than on owning its own state
MEASUREMENT_RESIDUAL = Candidate-A cost / tx-size / min-ADA / batch-fan-in figures and the live-boundary smoke are a downstream implementation-sizing and live-boundary gate — required for A's implementation, never the selection reason, never fabricated or back-filled; the B/C comparison artifacts are deferred/withdrawn honestly
RESIDUAL_RISKS = (1) A-implementation sizing unmeasured (downstream); (2) permissionless inception spawns one global UTxO per AID — min-ADA/UTxO-set bloat, deposit-mitigated not eliminated; (3) the transient inception-cage create/abandon surface is deposit-funded but bounded, not free; (4) emergency freeze (R-FRZ) is still a shared, attacker-contendable registry — a named downstream dependency to re-cut sovereign; (5) batched dApp fan-in needs one CIP-31 reference input per acting AID, tx-size/ex-unit sizing downstream
RKEL_CLASSIFICATION = preserved — R-KEL stays the on-chain checkpoint over settled R-ID, not a watcher-attested mirror
CAGE_INVARIANTS = preserved — the #99 cage predecessor/version continuity, output confinement, owner-authorized-against-authenticated-AID, and exact burn/lifecycle invariants carry over to the per-AID checkpoint
```

## Selected — Candidate A: the sovereign per-AID checkpoint UTxO

Each registered AID's current-authority checkpoint lives in its **own sovereign,
per-AID, quantity-one uniquely-tokenized UTxO** — asset id
`(checkpoint_policy_id, aid_asset_name)`, current key state in the inline
`CheckpointDatum`, normal rotation a `delta = 0` continuing-output transition
(`seq + 1`), discovery a **generic multi-asset `(policy_id, asset_name)` index lookup**
(any indexer / node / sidecar — **not** a bespoke/authoritative QVI-owned `AID → UTxO`
directory). **A is selected** because the **sovereignty invariant holds by
construction**: unrelated AIDs cannot spend, serialize, or block another AID's
checkpoint. Sovereignty and unrelated-AID isolation are the **load-bearing** criteria,
independent of any throughput measurement.

## Rejected — Candidate B: single/global MPFS checkpoint-root UTxO

**Rejected.** A single/global/shared checkpoint-root UTxO **serializes unrelated
identities** on one contended UTxO: honest and hostile writers queue behind the same
tip, so one AID's liveness depends on every other AID's write cadence — the opposite of
sovereignty. Residual (had it been chosen): A12 registry contention, highest emergency
latency.

## Rejected — Candidate C: lane-sharded MPFS

**Rejected.** Its lane assignment `lane = f(cesr_aid)` is a **public, grindable**
function: a permissionless attacker can grind AIDs until `f` lands in a **chosen
victim's lane** and spam it. More fundamentally, C makes an AID's sovereignty **depend
on shard machinery** (K, `f`, re-shard migration) rather than on the AID owning its own
state — sovereignty contingent on shard parameters is not sovereignty.

## Residual risks (honest)

- **A-implementation sizing is unmeasured** — Candidate-A cost / tx-size / min-ADA /
  batch-fan-in and the live-boundary smoke are a **downstream implementation gate**,
  not performed here, **never fabricated** and **never** the reason A was chosen.
- **UTxO-set / min-ADA bloat** — permissionless inception spawns one global UTxO per
  AID; deposit-mitigated (`bond_reg`), not eliminated.
- **Transient inception-cage create/abandon** surface — deposit-funded timeout/reclaim,
  bounded not free.
- **Emergency freeze (R-FRZ)** — still a **shared, attacker-contendable** registry; the
  sovereign emergency path **must not reintroduce a shared attacker-contendable UTxO**.
  Re-cutting R-FRZ sovereign is a **downstream dependency**, not absorbed here.
- **Batched dApp fan-in** — A removes MPF proofs but needs **one CIP-31 reference input
  per distinct acting AID**; tx-size / ex-unit / live-node cost is a downstream sizing
  gate.

## Preserved (not reopened)

- **R-KEL classification preserved** — R-KEL remains the on-chain cryptographic
  checkpoint over settled R-ID, **not** a watcher-attested / mirror-root mirror.
- **#99 cage invariants preserved** — predecessor/version continuity, output
  confinement, owner-authorized-against-authenticated-AID, and exact burn/lifecycle
  carry to the per-AID checkpoint (population-1-per-AID cage shape).
- **#91 logical decisions preserved** — MPFS-with-oracle registration/unicity,
  oracle-gated registration + permissionless challenge, and the hybrid genesis are
  fixed inputs; A is the **advance-store** the registered leaf is promoted into, not a
  reopening of registration unicity.
