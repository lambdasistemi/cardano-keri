# The registry as an MPFS instance

The AID registry ruled by D-024 — one UTxO holding the MPF root of every AID
ever registered, with registration inserting under an absence proof and
minting the checkpoint token in the same transaction — built as a cage of
[cardano-mpfs-onchain](https://github.com/cardano-foundation/cardano-mpfs-onchain)
on its plugin path. This page names the Lean predicates behind every claim.
The model is `lean/CardanoKeri/Registry.lean`; the theorems are
`lean/CardanoKeri/RegistryGoals.lean`; the simulator is
[Registry Simulator](../simulator/registry/index.html).

## Why a cage

D-024 as first stated has every registration spend the registry UTxO
directly: "inceptions queue on the registry UTxO." Cardano has no queue for
conflicting spends. Each node's mempool keeps the first spend it hears and
never switches (the consensus layer's *linear consistency*, IOG technical
report, §13.1); the slot leader includes its own first arrival; losers fail
phase 1 on the spent input and pay nothing, but must rebuild the absence
proof against the new root. A burst of N registrants clears in about N
blocks with O(N²) rebuilds, and the latency-advantaged ones go first.

The cage shape moves the race away from the users. A registration is a
**request** — an inbox UTxO that contends with nothing — and a
**fold** spends the registry with many requests at once. Folders race;
requesters are served by whichever fold lands, and can fold their own
request. The rebuild cost of a lost race falls on folders. The mpfs changes
this needs are the plugin-cage epic
[cardano-foundation/cardano-mpfs-onchain#99](https://github.com/cardano-foundation/cardano-mpfs-onchain/issues/99):
replace semantics for the `stake_script` hook (#79), the hook and the owner
pinned and empty folds refused (#100), processed-request value routed by the
plugin (#101), and the plugin contract with a mint-coupled reference plugin
(#102).

## The machine

`Sys` is the registry UTxO (`gen`, `plugin`, `root`), the tokens (`live`,
`tomb`), and the inbox (`requests`, `nextReq`). The root is the set of
registered AIDs; the MPF absence proof is membership. Tokens are lists so
that uniqueness is a theorem about counts.

`Action` is exactly the redeemers of the cage family and the checkpoint
edges that touch a token:

| action | actor | guard (`stepFn`) | effect |
|---|---|---|---|
| `contribute aid owner submittedAt` | anyone | none | a request; `D + tip` deposited |
| `fold folder gen plugin batch` | anyone | `gen = s.gen`, `plugin = s.plugin`, `batch ≠ []`, then per entry | registry spent (`gen + 1`); processed: row inserted, token minted, `D` locked; rejected: `D` refunded to the owner; `tip` per request to the folder |
| `retract req` | the owner | `inPhase2` | `D + tip` back to the owner; registry untouched |
| `close aid` | current quorum | `aid ∈ live`, `env.quorum aid` | token burned, row deleted, registry spent |
| `convict aid` | a proof | `aid ∈ live`, `env.duplicity aid` | token becomes a tombstone; the row stays; registry not spent |

Per batch entry (`applyBatch`): `process` needs `inPhase1`,
`env.inception r.aid`, and `r.aid ∉ acc.root`; `reject` needs `rejectable`.
An entry naming a request the inbox does not hold — including one the same
batch already consumed — refuses the whole fold.

The phases are the cage's, at a point: `inPhase1 p r now :=
now < submittedAt + process`, `inPhase2` the next `retract` slots,
`rejectable := submittedAt + process + retract ≤ now ∨ now < submittedAt`.
A future `submitted_at` is in phase 1 and rejectable at once, as on chain.

The evidence is an `Env` of three predicates the plugin and the checkpoint
policy verify: `inception` (the #114 rule), `quorum`, `duplicity`.

## Row if and only if token

The design under test: an AID is in the root exactly when it has a live
token or a tombstone (`Inv.rowIffToken`). Two consequences fall out:

- **a closed AID may return.** Close deletes the row with the burn
  (`R4_close_deletes_row`); the absence proof then succeeds for a fresh
  request (`R4_reregistrable`).
- **a convicted AID never can.** Conviction keeps the token as a tombstone
  and the row with it (`R3_tomb_permanent`); no fold can process that AID
  again (`R3_convicted_never_processed`) and the tombstone cannot be closed
  (`R3_convicted_not_closable`).

This differs from D-028 as first stated ("the registry row stays" after
close). The token-tied invariant keeps mint-once *while a token exists*, which
is what consumers need, and makes the difference between close and
conviction a difference in what the checkpoint validator allows, not a
registry flag.

## The theorems

| id | claim | Lean |
|---|---|---|
| R1 | row iff token; an AID absent from the root has no token; a registered AID cannot be processed again | `R1_row_iff_token`, `R1_absent_no_token`, `R1_registered_refused` |
| R2 | at most one live checkpoint per AID; a tombstone is never live | `R2_one_live_checkpoint`, `R2_tomb_not_live` |
| R3 | conviction is permanent | `R3_tomb_permanent`, `R3_convicted_never_processed`, `R3_convicted_not_closable` |
| R4 | a closed AID may return | `R4_close_deletes_row`, `R4_reregistrable` |
| R5 | the plugin is pinned | `R5_plugin_pinned` |
| R6 | the generation moves exactly on registry spends; requests and retracts never contend | `R6_gen_step`, `R6_requests_never_contend`, `R6_spend_is_fold_or_close`, `R6_fold_advances` |
| R7 | a stale fold is refused with no state change; one fold per generation | `R7_stale_fold_refused`, `R7_one_fold_per_generation` |
| R8 | an empty fold and a plugin swap are refused | `R8_empty_fold_refused`, `R8_plugin_swap_refused` |
| R9 | requester exit: retract in phase 2, rejection by anyone when rejectable, neither elsewhere | `R9_retract_enabled`, `R9_retract_needs_phase2`, `R9_reject_enabled`, `R9_reject_needs_rejectable`, `R9_process_needs_phase1` |
| R10 | the phases are exclusive | `R10_phase1_phase2_exclusive`, `R10_phase2_reject_exclusive`, `R10_honest_phase1_reject_exclusive` |
| R11 | value: `D` locked per process, `D` refunded per reject to a request owner, `tip` per request to the folder, every request accounted for | `R11_fold_value`, `R11_retract_value`, `R11_contribute_value`, `R11_token_edges_move_no_value` |
| R12 | a row leaves the root only by close and enters only by fold | `R12_row_leaves_only_by_close`, `R12_row_enters_only_by_fold` |

The invariant is proved reachable-preserved (`inv_init`, `inv_step`,
`reach_inv`); the batch lemmas (`applyBatch_inv`, `applyBatch_root_mono`,
`applyBatch_value`, `applyBatch_process_registered`) carry the fold. Forty-nine
declarations, no `sorry`, standard axioms only. Eleven guard mutants, eleven
reds for the right reason: `lean/REGISTRY-MUTANTS.md`.

## What the model does not say

- **Cryptography.** Evidence is a table; the inception rule, the quorum and
  the duplicity proof are decided outside the machine.
- **The checkpoint's life.** Rotations, bonds, poison and the consumer's
  predicate are `CardanoKeri.Checkpoint`; here a checkpoint is its token.
- **Fees.** Under #101 the folder funds the transaction fee; the model moves
  bonds and tips only.
- **Ordering among folders.** Which fold lands is first arrival at the slot
  leader. The model says a stale fold is refused; it does not say who wins.
- **Censorship.** A folder may omit a request; the remedy is folding it
  oneself. Under capacity this is economic deterrence, not a proof.
