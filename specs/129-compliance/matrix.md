# #129 — Compliance matrix: merged `main` vs the design of record

Audit of the merged mid-transition validator (post-PR #125, HEAD `5f701b6`)
against: the LOCKED permissionless-freeze design note (incl. the burn axiom,
2026-07-22), the epic-owner verification note, epic #24/#21 Technical
contracts, and the 21 proved Lean theorems on this branch. Read-only audit;
classifications:

- **COMPLIANT** — delivered code matches the design/theorems exactly.
- **PLANNED(→ticket)** — divergence already assigned to a pipeline slice.
- **UNPLANNED(→Q-Cnn)** — divergence with no assignment; filed under
  `/tmp/keri-24/t129/questions/`.

Commands run for evidence (all read-only): `scripts/check-lean-traceability.sh`
(pass, "21 Lean theorems mapped"), `just measure-checkpoint` (six rows pass,
values below), `just check-onchain` (full Aiken suite, exit 0),
`lake build` in `lean/` (success, zero `sorry`, no custom axioms).

**Verdict summary: 47 rows — 33 COMPLIANT, 9 PLANNED, 5 UNPLANNED (Q-C01..Q-C05). GO (see final page).**

---

## 1. State-machine fidelity (delivered Aiken transitions vs Lean `Step`)

| # | Element | Lean | Delivered code | Class | Evidence |
|---|---------|------|----------------|-------|----------|
| 1.1 | Arm guard: permissionless, only on provably-behind ACTIVE | `Step.arm` requires `env.kel.behind k` (Lifecycle.lean:244-247) | Freeze redeemer admitted only from ACTIVE role; evidence EE0-EE9-bound then `freeze_predicate` demands a witnessed rotation strictly ahead (`native_sn > tip.native_sn`) spending the tip's own pre-rotation commitment at `next_threshold` with ≥ `toad` receipts — i.e. exactly the real successor event | COMPLIANT | checkpoint.ak:133-137,330-366; enforcement.ak:299-334 |
| 1.2 | Arm deadline: `deadline = validity upper bound + W_freeze`, raw endpoint, no inward normalization | verification note obligation 2 | `expect interval.Finite(upper) = validity_range.upper_bound.bound_type; deadline = upper + freeze_window`; ArmedV1 wraps checkpoint + `hunter_pkh` + `deadline` | COMPLIANT | checkpoint.ak:350-354; freeze_bond.ak:106-121 |
| 1.3 | Arm output shape: full value carried, same token, exact ArmedV1 datum, no mint | `carried(armed) = min+D+B` (Lifecycle.lean:143) | `state_output.value == own_input.output.value`; one-element filter at ARMED address; datum equality vs reconstructed ArmedV1; empty own-policy mint | COMPLIANT | checkpoint.ak:355-365 |
| 1.4 | Arm once per behind-state / ARMED exclusive window | `armed_exclusive_window` (Goals.lean:161-167) | From ARMED the dispatcher admits only `ClaimFreeze` and `Convict`; no re-arm path exists (Freeze from ARMED → `fail`) | COMPLIANT (delivered window is strictly narrower: advance-response staged → row 1.8) | checkpoint.ak:132-187 |
| 1.5 | Claim: at/after deadline STRICTLY by validity lower bound (`d ≤ t`) | `Step.claim` `hdeadline : d ≤ t` (Lifecycle.lean:250-253) | `expect interval.Finite(lower); expect lower >= deadline` | COMPLIANT | checkpoint.ak:387-389 |
| 1.6 | Claim pays exactly `B` to the RECORDED hunter (claimer chooses nothing but an index); state → FROZEN at same position; value minus exactly `B`; datum unchanged; no mint | `abandonment_pays_exactly_B` (Goals.lean:318-326) | Hunter output at `from_verification_key(hunter_pkh)` (from the ARMED datum) with value `from_lovelace(freeze_bond)` and `NoDatum`; FROZEN successor keeps `input value − B`; `successor == tip`; empty mint | COMPLIANT | checkpoint.ak:390-406 |
| 1.7 | Response semantics ready: response strictly before deadline (`t < d`) | `Step.advanceArmed` `hwin : t < d` (Lifecycle.lean:228-230) | Helper `response_before_deadline: u < deadline` (STRICT) exists with Haskell-generated vectors; not yet dispatched | COMPLIANT (helper) / PLANNED(→#115) for the live branch | freeze_bond.ak:124-130 |
| 1.8 | ARMED → advance-response (B reconstituted), FROZEN thaw re-post, ordinary advance | `Step.advanceArmed/advanceFrozen/advanceActive` | Advance redeemer falls to `_ -> fail`; staged `validate_advance` admits only ACTIVE\|FROZEN and checks V3 ≥ `min + d_reg` without `B` — pre-bond shape, unreachable, replaced by #115 | PLANNED(→#115: permissionless advance, response + thaw + `B` continuity) | checkpoint.ak:186 (`_ -> fail`), 548-603 |
| 1.9 | Register (Absent → Active 0, escrow `min+D+B`) | `Step.register` (Lifecycle.lean:217-220) | Mint branch validates parameter floors then unconditionally `fail`s; staged `validate_register` (InceptionMessage fresh-sig layer, R8 `min+d_reg` without B) is unreachable | PLANNED(→#114: permissionless bridging, `D_reg+B` escrow, delete InceptionMessage layer) | checkpoint.ak:109-114, 263-324 |
| 1.10 | Close / CLOSING machine (`closeIntent`, `challengeClose`, `finalizeClose`, `W_close`, role `0x03`) | `Step.closeIntent/challengeClose/finalizeClose` | `Close -> fail` via `_ -> fail`; no CLOSING role exists | PLANNED(→#117: close + resolution; role `0x03`) | checkpoint.ak:186; role.ak:11-27 |
| 1.11 | Reap machine (reapIntent Frozen/Closing, advance-void, reapExecute, `W_reap`) | `Step.reapIntent*/advanceReaping/reapExecute` (Lifecycle.lean:313-338) | Absent entirely | PLANNED(→#117 per burn-axiom ruling 2: "#117 owns the exit paths … folds reap + stale-CLOSING-reap") | design note:115,119 |
| 1.12 | Convict from ACTIVE: `D_reg`+`B` → convictor | `Step.convictActive` outflows D,B (+minAda under burn) | Exact lovelace-only `NoDatum` payout of `d_reg + freeze_bond` to `convictor_pkh` at an explicit index | COMPLIANT (payout routing) — min-ADA residue is row 1.15 | checkpoint.ak:411-436, 530-541 |
| 1.13 | Convict from ARMED: `D_reg` → convictor, `B` → the RECORDED armed hunter, distinct outputs | `Step.convictArmed` (Lifecycle.lean:285-289) | `d_reg` → convictor and `freeze_bond` → `hunter_pkh` from the ARMED datum; `convictor_output_index != hunter_output_index` enforced | COMPLIANT | checkpoint.ak:440-465 |
| 1.14 | Convict from FROZEN: `D_reg` → convictor only (B already gone) | `Step.convictFrozen` (Lifecycle.lean:292-296) | `d_reg` → convictor; no bond output | COMPLIANT | checkpoint.ak:469-488 |
| 1.15 | Convict terminality: BURN to `.absent`, min-ADA freed to convictor, tombstone deleted | `Step.convictActive` → `.absent`, minAda outflow (Lifecycle.lean:278-282); `convict_burns_and_no_aid_bar` | Convict writes the exact TOMBSTONE output (role `0x01`, `TombstoneV1{cesr_aid, native_sn, evidence_said}`, min-ADA + token) and forbids any own-policy mint (incl. burn) | PLANNED(→ no later than #115: convict-burn; negative bytes toward the size stop). Full tombstone deletion map: inventory below | checkpoint.ak:493-526; design note:114 |
| 1.16 | TOMBSTONE terminal while it exists: no admitted redeemer | (pre-burn F11) | `classify_spend_input` → `TerminalTombstone`; Convict arm `TerminalTombstone -> fail`; all other redeemers `_ -> fail`; unit vectors `t116_s5_f11_reject_advance/close_from_terminal_tombstone` | COMPLIANT (as staged intermediate) | checkpoint.ak:184, 239-241; checkpoint_tests.ak:2495,2514 |
| 1.17 | No legacy direct ACTIVE→FROZEN freeze path | ARMED is mandatory intermediate | FROZEN output is produced ONLY by `validate_claim` (from ARMED); Freeze from ACTIVE produces ARMED; `freeze_output_predicate` (the #106 direct-freeze shape) survives as an uncalled schema-layer relic, unreachable from the validator | COMPLIANT (relic listed in the deletion map below) | checkpoint.ak:355-357,394-396; enforcement.ak:537-550 |
| 1.18 | No message-layer branch reachable despite staging | design: layers deleted by #114/#115 | Mint `fail`s before any registration predicate; Advance/Close hit `_ -> fail` before `advance_predicate`; `else(_) fail` blocks other purposes | COMPLIANT (unreachable; deletion is #114/#115 scope) | checkpoint.ak:109-114,186,190-193 |
| 1.19 | Convict evidence gate: rot at same sn, same reveal, controller threshold, ≥ toad receipts, real conflict axis (`kt/n/nt/bt`, witness set NOT an axis) | epic #24 contract; #106 ratified predicate | `convict_predicate` ordered checks 1-5 exactly; `forward_agrees` excludes the witness set with the documented phantom-convict rationale | COMPLIANT | enforcement.ak:225-267 |
| 1.20 | O1: all signatures over full `event_bytes`, never the SAID | epic #24 contract | Binder carries `event_bytes` unchanged; `verified_positions/verified_keys/count_receipts` all verify over `msg = event_bytes`; no SAID recomputation exists | COMPLIANT | enforcement.ak:5-8,341-431 |

**TOMBSTONE deletion map for #115** (the planned-delta inventory, precise):
`onchain/validators/checkpoint.ak` — `Tombstone` import (:54), `TerminalTombstone` classify arm (:239-241) + dispatch reject (:184), `validate_convict_terminal` tombstone output shape (:509-524);
`onchain/lib/cardano_keri/checkpoint/role.ak` — `Tombstone` variant (:14), tag `0x01` (:24), classify arm (:44-45);
`onchain/lib/cardano_keri/checkpoint/enforcement.ak` — `TombstoneV1` (:441-445), `AddressRole.Tombstone` (:452-456), `OutputDatum.TombstoneOutput` (:461-463), `convict_output_predicate` (:495-515), plus the stale `freeze_output_predicate` direct-freeze shape (:537-550);
`offchain` — `Cardano.KERI.AID.Checkpoint.Enforcement` (TombstoneV1 mirror), `FreezeBond.hs` `roleTag Tombstone` (:89), `LifecycleModel.hs` `Tombstone` state (:84) + 4 convict targets, `GenEnforcementVectors.hs`, `GenLifecycleTraceVectors.hs`;
tests/vectors — `checkpoint_tests.ak` (F11 suite), `enforcement_tests/vectors.ak` (`golden_tombstone`), `lifecycle_model{,_tests,_vectors}.ak`, `role_tests.ak`, `freeze_bond_{tests,vectors}.ak`, `checkpoint_measurements.ak` convict rows, `FreezeBondSpec/LifecycleModelSpec/EnforcementSpec`.

## 2. Escrow arithmetic

| # | Element | Design | Delivered | Class | Evidence |
|---|---------|--------|-----------|-------|----------|
| 2.1 | Input reserve by role: ACTIVE/ARMED `min+D+B`, FROZEN `min+D` | `carried` (Lifecycle.lean:140-146) | `classify_spend_input` enforces `checkpoint_min_ada + d_reg + freeze_bond` (ACTIVE, ARMED) and `checkpoint_min_ada + d_reg` (FROZEN), plus exactly the one derived AID token | COMPLIANT | checkpoint.ak:207-244, 249-259 |
| 2.2 | Claim value equation: continuing FROZEN = input − exactly `B`; hunter gets exactly `B` | `Step.claim` | `merge(from_lovelace(-freeze_bond))` equality + exact hunter output | COMPLIANT | checkpoint.ak:390-401 |
| 2.3 | Arm value equation: unchanged | `carried(armed)=carried(active)` | full-Value equality | COMPLIANT | checkpoint.ak:359 |
| 2.4 | Convict payouts exact, lovelace-only, `NoDatum`; surplus stays ordinary change | verification note obligation 3 | `expect_exact_payout` equality against `from_lovelace(n)` + `NoDatum`; measurement fixtures prove 42 ADA surplus rides through as change | COMPLIANT | checkpoint.ak:530-541; specs/116-freeze-bond/MEASUREMENTS.md:31-34 |
| 2.5 | Mechanical floors 5,000,000 each for `D_reg` and `B`; one-below rejected | design:20,80 | `registration_deposit_floor = 5_000_000`, `freeze_bond_floor = 5_000_000`; every mint/spend entry re-validates; one-below negative vectors on both sides | COMPLIANT | registration.ak:55-59; freeze_bond.ak:12-18; checkpoint.ak:110-112,122-124; checkpoint_tests.ak:306,800; FreezeBondSpec.hs:62-64; freeze_bond_tests.ak:39-42 |
| 2.6 | `W_freeze` a deployment parameter with a floor | design:47-49 | Validator parameter `freeze_window`; floor `> 0` (`freeze_window_valid`), re-checked on every entry; `NonPositiveFreezeWindow` deadline error | COMPLIANT (floor = 1 time unit; W_close/W_reap params arrive with #117) | freeze_bond.ak:20-23,110-113 |
| 2.7 | Parameters generic — no compiled magnitudes beyond floors/reference fixtures | brief dim 2 | `d_reg`, `freeze_bond`, `freeze_window` are applied validator parameters; compiled constants are the two 5M floors, `checkpoint_min_ada = 2_000_000` (documented conservative ledger floor, matches harness/vectors), and the ratified 1..1024 `event_bytes` wire bound | COMPLIANT | checkpoint.ak:56-62,101-108; enforcement.ak:78-80 |
| 2.8 | `B` reconstitution on ARMED-response; thaw re-post; register escrows `B` | `Step.advanceArmed/advanceFrozen/register` | Not delivered (paths staged) | PLANNED(→#115 response/thaw, →#114 register escrow) | rows 1.8/1.9 |

## 3. Role surface

| # | Element | Design | Delivered | Class | Evidence |
|---|---------|--------|-----------|-------|----------|
| 3.1 | Role map: ACTIVE bare, FROZEN `0x00`, TOMBSTONE `0x01`, ARMED `0x02` (CLOSING `0x03` held #117) | epic #24 contract; specs/116-enforcement/spec.md:245-258 | `role_tag`: Active None, Frozen `#"00"`, Tombstone `#"01"`, Armed `#"02"` | COMPLIANT (TOMBSTONE tag itself = planned deletion, row 1.15) | role.ak:11-27 |
| 3.2 | Ratified derivation: `role_hash = blake2b_224("cardano-keri/checkpoint/role/v1" ‖ h ‖ tag)`; address = payment `h` + staking `role_hash`; bare for ACTIVE | specs/116-enforcement/spec.md:245-246 | Exact formula; `with_delegation_script(hash(policy, role))`; staking axis is marker-never-authority | COMPLIANT | role.ak:17,29-40 |
| 3.3 | Haskell mirror parity of the derivation | traceability culture | `roleDomain = "cardano-keri/checkpoint/role/v1"`, same tags, golden role vectors | COMPLIANT | FreezeBond.hs:86-100; role_tests.ak |
| 3.4 | ZERO REGISTRY/BOUNTY/MPFS-registration/unicity remnants in production on/offchain | epic #24 contract ("no global unicity structure…") | `grep -rniE "registry\|bounty\|unicity\|mint.once"` over production code: only (a) the lifecycle mirrors' `Bounty` TransferKind (mirrors Lean `.bounty` — legitimate), (b) `validators/types.ak:58` cage `identity_root` (value-cage MPF — out of scope per audit brief). REGISTRY `0x02`/BOUNTY `0x03` roles do not exist (`0x02` is ARMED) | COMPLIANT | grep evidence; role.ak:11-27; specs/116-enforcement/spec.md:54,258 |
| 3.5 | Consumers/status-blind fail-closed by address (O4) | verification note obligation 1 | Address-per-role; ARMED wraps the checkpoint datum with `hunter_pkh`+`deadline` (wire type ArmedV1, versioned Constr 0) | COMPLIANT | freeze_bond.ak:29-36; role.ak:29-40 |

## 4. Staging honesty

| # | Element | Expected | Delivered | Class | Evidence |
|---|---------|----------|-----------|-------|----------|
| 4.1 | Register fail-closed in unit vectors | reject vectors | `t116_r2_stage_reject_register_{2key,7key,witnessed,weighted,extra_input}` all `fail`-annotated, suite green | COMPLIANT | checkpoint_tests.ak:219-279; `just check-onchain` exit 0 |
| 4.2 | Advance fail-closed in unit vectors (incl. thaw and ARMED response) | reject vectors | `t116_r2_stage_reject_advance_*` incl. `_thaw_from_frozen` (:1380), `t116_r2_stage_reject_armed_advance_reserved_for_115` (:3559), `t116_r2_stage_reject_active_advance` (:3542) | COMPLIANT | checkpoint_tests.ak |
| 4.3 | Close fail-closed in unit vectors | reject vector | `t116_r2_stage_reject_close` (:3593) | COMPLIANT | checkpoint_tests.ak |
| 4.4 | Real-node smoke: staged closures rejected AT the production applied script | e2e-vs-staging ruling (design:105) | CheckpointE2ESpec asserts Register/Advance/Close rejections carry `rejectionReachedProductionScript` evidence; response-boundary cases cover both deadline sides; the two full freeze scenarios compiled + `pendingWith "#114 Register is closed and #115 Advance is closed"`; wired as CI job `e2e` (nix build .#checks.e2e), main green | COMPLIANT | offchain/e2e/CheckpointE2ESpec.hs:33-60; .github/workflows/ci.yml:104-119; run 29901468498 success |
| 4.5 | 32 KiB genesis confined; semantic-only | A-015 | `e2eGenesis` edits ONLY `.protocolParams.maxTxSize` 16384→32768 and `cmp`-proves the rest byte-identical; exported only by the e2e runner app. Note: the runner hosts the cage batch-2 smoke too, but no size-sensitive cage assertion runs there — the boundary evidence is the sweep | COMPLIANT (with note) | offchain/flake.nix:294-316,324-335 |
| 4.6 | Production-cap cage sweep untouched on 16,384 | brief dim 4 | `sweepRunner` pins `E2E_GENESIS_DIR` to the pristine `cardano-node-clients` genesis ("Preserve the production 16384-byte cap"); sweep job asserts per-batch node outcomes + committed-artifact consistency check | COMPLIANT | offchain/flake.nix:349-360; ci.yml:121-143 |
| 4.7 | NON-DEPLOYABLE banner on the e2e path | Q-015/A-015 | Printed at every staged devnet start; exact size tuple mechanically asserted each run | COMPLIANT | CheckpointTxBuilder.hs:283,347-405 |

## 5. Traceability SEMANTIC fidelity (16 live rows + 5 PENDING)

Chain: Lean theorem → QuickCheck property over the Haskell mirror → generated
verdict vectors → Aiken parity test. Gate `scripts/check-lean-traceability.sh`
passes (existence + order + vector regeneration). **Structural finding first:
the executable mirror is the PRE-burn machine** (Tombstone, no reaping;
`LifecycleModel.hs:78-85`, `lifecycle_model.ak:25-30`) while the theorems are
proved over the post-burn machine → Q-C01. Additionally the gate itself is not
CI-enforced → Q-C04. Per-row:

| csv row | Lean theorem | Judgment | Reason (file:line) |
|---------|--------------|----------|--------------------|
| 6 | advance_totality | PARTIAL | QC covers active/armed(±deadline, claim→thaw)/frozen/closing (LifecycleModelSpec.hs:79-93, 454-480); the `reaping` branch of the ∀ is unsampled (mirror lacks it) — Q-C01(4) |
| 7 | no_absorbing_busy_state | PARTIAL | successor exhibited per live mirror state with `closeCapabilities` = the ratified `hcap` (:95-102, 583-590); reaping missing — Q-C01(4) |
| 8 | adversarial_advance_is_progress | PARTIAL | direct: any admitted advance lands `Active (k+1)` with `hasEvent (k+1)` over 4 of 5 live source states (:186-193, 277-285); reaping missing — Q-C01(4) |
| 9 | bounded_churn | **MISMATCH → Q-C01(1)** | prop asserts `j <= i + 3` (:112) on the no-reap machine; the theorem states `j ≤ i + 4` with `hnoreap` (Goals.lean:137); the csv row carries no annotation; Aiken vector is one 2-stall trace (lifecycle_model_tests.ak:120-137) |
| 10 | armed_exclusive_window | FAITHFUL | full action-universe filter, admitted ⊆ {Advance, Convict}, Advance present, fork randomized (:195-202); Aiken admitted == [Advance] at slot 9 < deadline (:139-149) |
| 11 | bond_transfer_only_via_elapsed_window | FAITHFUL (sampled) | arm-or-challengeClose pairing, `slot_i + Wf ≤ slot_j`, no intervening advance, exact `Transfer hunter B Bounty` membership, ¬fork env (:116-131); necessity direction sampled on generator-shaped traces only (header-acknowledged sampling) |
| 12 | abandonment_pays_exactly_B | FAITHFUL | exact outflow append to the RECORDED hunter, `Frozen k`, deposits unchanged (:204-214); Aiken mirror test (:169-180) |
| 13 | frozen_implies_true_silence | FAITHFUL (sampled) | Frozen ⇒ arm/challenge + claim ≥ Wf apart, no advance between (:133-146); positive-shape generator; early-claim rejection covered by the wire-level deadline vectors (freeze_bond_tests.ak) and validator vector (checkpoint_tests) |
| 14 | close_lie_always_voidable | FAITHFUL | behind-Closing admits both voids (:216-220) |
| 15 | close_at_tip_unchallengeable | FAITHFUL | both voids rejected at tip + finalize admitted at deadline (:222-227) |
| 16 | current_state_is_quiet | FAITHFUL | admitted == [CloseIntent] over the full action universe, ¬fork (:229-238) |
| 17 | value_conservation | PARTIAL | balance preserved per constructor — but over the pre-burn `carried` (Tombstone keeps min_ada, LifecycleModel.hs:148); burn/reap flows unexercised — Q-C01(3) |
| 18 | value_conservation_trace | PARTIAL | same machine gap — Q-C01(3) |
| 19 | convict_dominance | PARTIAL | admissibility from the 4 mirror live states checked (:248-252); the theorem's "target = `.absent`" clause untested (mirror target is Tombstone) — defensible split with PENDING row 20, but un-annotated — Q-C01(2) |
| 20 | convict_burns_and_no_aid_bar | PENDING — **correctly assigned** | burn/no-bar needs the post-burn mirror; legacy sibling `prop_tombstone_terminal_but_no_aid_bar` still exists un-mapped (:254-264) as the current machine's record |
| 21 | replay_convergence | FAITHFUL | register + N−1 advances reach Active(tip) in exactly N txs, N random (:157-168) |
| 22 | close_cycle_requires_elapsed_window | FAITHFUL (sampled) | finalize immediately preceded by its intent, `+Wc` elapsed (:170-182); positive-shape generator; early-finalize rejection guarded by the mirror dispatch guard (`deadline <= t`, LifecycleModel.hs:233) |
| 23 | dead_end_freedom | PENDING — correctly assigned | needs reap machinery |
| 24 | reap_voidable | PENDING — correctly assigned | needs reaping state |
| 25 | reap_requires_untouched_window | PENDING — correctly assigned | needs reap steps |
| 26 | frozen_reap_requires_two_windows | PENDING — correctly assigned | needs reap steps |

Gate enforcement: script exists and passes locally; **not invoked by
`.github/workflows/ci.yml`, and no CI job builds the Lean library at all** —
UNPLANNED → Q-C04 (design: "breaks CI, not trust", design note:91).

## 6. Measurements & budget

| # | Element | Expected | Observed | Class | Evidence |
|---|---------|----------|----------|-------|----------|
| 6.1 | Six ≥25%-headroom rows reproducible from committed artifacts | MEASUREMENTS.md table | `just measure-checkpoint` re-run this audit: arm_7key 6,806,289/2,990,090,781; claim 654,656/213,846,973; convict_active 1,644,269/707,052,786; convict_armed 1,751,278/746,925,761; convict_frozen 1,693,140/727,347,040 — byte-exact vs the doc; jq gate asserts exact title set, pass status, and the 10.5M/7.5B limits | COMPLIANT | specs/116-freeze-bond/MEASUREMENTS.md:36-46; justfile:181-212; run output |
| 6.2 | Recipe intact and title-pinned (staged paths cannot be substituted) | brief dim 6 | exact-title jq check over the six required `measure_checkpoint_*` | COMPLIANT | justfile:190-197 |
| 6.3 | 16,133 budget + banner in PR #125 body | recorded | banner + `19,565/19,816/251/16,133/3,432` table + #115 hard-stop sentence | COMPLIANT | PR #125 body:15,66-72 |
| 6.4 | 16,133 budget + banner on the e2e output path | recorded + asserted | banner every staged run; exact tuple mechanically asserted (drift fails) | COMPLIANT | CheckpointTxBuilder.hs:283,399-405 |
| 6.5 | 16,133 budget + banner in the committed measurement docs | recorded | ABSENT — MEASUREMENTS.md has only "non-deployable HEAD" (:49); no in-tree doc carries 19,565/16,133/3,432 | UNPLANNED → Q-C05 | grep over docs/ + specs/ |

## 7. Docs ↔ code honesty

| # | Element | Observed | Class | Evidence |
|---|---------|----------|-------|----------|
| 7.1 | Register/Advance/Close described as staged/held wherever the target design is narrated | Blog "Staged implementation boundary" admonition; trust-model "deliberately not deployable: #116 currently opens only Arm, Claim, and Convict; #114 will open… #115… #117…"; deck disclaimer "ratified final-lifecycle framing, not a deployment claim" | COMPLIANT | blog:189-190; trust-model.md:138-140; milestones-deck/index.html:146 |
| 7.2 | Convict narrated as BURN while delivered Convict writes a tombstone; Convict listed among the OPEN transitions; no doc discloses the delivered tombstone shape | trust-model:96-101,144-148; blog:180; overview.md:124-126; identity-on-cardano:371; PROMPT.md:144 — vs checkpoint.ak:493-526 | UNPLANNED → Q-C02 | ibid |
| 7.3 | Freeze "not bounty-paid" fragments surviving with no owning ticket (design named them now-wrong; #116's ratified docs slice scoped 3 files and fixed them; these two are outside every pipeline slice) | identity-on-cardano/index.html:371; super-watcher.md:70 | UNPLANNED → Q-C03 | specs/116-freeze-bond/spec.md:301-309 |
| 7.4 | Registration narrative still fresh-signature-based ("squatting collapses to key theft", registration signed by the event's keys) | blog:71; specs/114-registration/spec.md:78 (old spec, ruled to be re-specced) | PLANNED(→#114 re-spec + its docs slice: registration narrative) | design note:74,78 |
| 7.5 | Advance narrative / AdvanceMessage layer docs | pending #115 docs slice | PLANNED(→#115) | design note:75,78 |
| 7.6 | Historical registry-era pages (freeze registry, absence proof, trie MPF, FrozenFatal re-registration bar) | All carry explicit superseded/rejected-lineage banners (#92/#68); reconciliation is the standing #84 ticket | COMPLIANT (banner-labeled history) | overview.md:15-27; identity-ops.md:3-33; aid-model.md:3-10 |
| 7.7 | Burn-axiom narrative ("conviction recorded in the transaction, in history"), two-primitives theorem, advance-totality/bounded-interference as normative invariants | Present and prominent: trust-model normative invariants section; blog per-move table + theorem framing; deck one-liner "anyone can project the public truth…" | COMPLIANT | trust-model.md:115-135; blog:160,180-185; milestones-deck:146 |

---

# GO / NO-GO — one page

## Verdict: **GO** for unpausing #114 → #115 → #117, with five filed riders (none blocks the code ground).

**Why GO.** Every DELIVERED on-chain transition matches the design of record
and the Lean `Step` relation exactly: arm/claim/convict guards, both deadline
endpoint comparisons (response strict `<`, claim `>=`), all value equations and
exact payouts (claim → recorded hunter only; convict routing per input role),
the ratified role formula, both 5M floors with one-below rejection on both
sides, and generic applied parameters. No legacy direct-freeze or reachable
message-layer path exists. Staging is honest three ways (unit vectors,
real-node production-script rejections in CI, docs labels for
Register/Advance/Close). The 21 theorems build clean (no `sorry`, no custom
axioms); the six ex-unit rows reproduce byte-exactly; the size hard-stop is
mechanically asserted on every e2e run. Every code divergence from the final
design is a KNOWN planned delta with a live assignment (#114 register+escrow+
message-layer deletion; #115 advance/response/thaw + convict-burn + the 3,432-
byte deployability stop; #117 close/reap/W_close/W_reap), and this matrix adds
the precise tombstone deletion map #115 needs.

**The five riders (all filed, none on-chain code):**

| Q | What | Proposed owner | Blocking? |
|---|------|----------------|-----------|
| Q-C01 | Live traceability rows silently assert the pre-burn mirror (churn `i+3` vs proved `i+4`; convict target clause untested; no reaping sampling; conservation over the old machine) | (a) one-line csv/README annotation NOW + (b) mirror upgrade with convict-burn ≤#115, reap coverage #117 | No — but the annotation should land before or with unpause; without it the csv overstates what CI checks |
| Q-C02 | Docs declare live Convict burns; merged Convict writes a tombstone; staging labels cover only Register/Advance/Close | one-line staged-boundary amendment; #115 docs slice or a docs-only commit under the pause | No |
| Q-C03 | Orphaned "not bounty-paid" fragments (identity-on-cardano deck, super-watcher.md) — no owning ticket | add to #115's docs-slice file list (or same docs pass as Q-C02) | No |
| Q-C04 | Traceability gate + Lean build absent from repository CI (design says "breaks CI, not trust") | CI-only fix; can land during the pause | No — but SHOULD land before #114 merges, else the pipeline's own map rows are honor-system |
| Q-C05 | 16,133/19,565/3,432 budget recorded only in PR body + e2e assertion, not in any committed doc | one section in specs/116-freeze-bond/MEASUREMENTS.md | No |

**Conditions that WOULD have forced NO-GO** (verified absent): any reachable
staged branch; any payout/deadline/value inequality vs the Lean relation; a
REGISTRY/BOUNTY/unicity remnant; a claim that a closed transition is live; a
non-reproducible measurement row; an unfiled divergence.

**Recommended unpause order (unchanged from the design):** land Q-C04 (CI) +
the Q-C01a annotation + the Q-C02/03/05 docs pass under the pause (no
production code, ~1 commit each), then #114 → #115 (convict-burn + tombstone
deletion map + size hard-stop) → #117 (close + reap), each with its docs and
E2E slice per the ratified staging ladder.

Audit rows: 47 — COMPLIANT 33, PLANNED 9 (1.7-live, 1.8, 1.9, 1.10, 1.11,
1.15, 2.8, 7.4, 7.5), UNPLANNED 5 (Q-C01..Q-C05).
