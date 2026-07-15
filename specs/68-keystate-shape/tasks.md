# Tasks: #68 sovereign `CheckpointDatumV1` wire-contract freeze

One `## Slice` section per bisect-safe commit. `[X]` is set when the slice is
reviewed + accepted (amended into the slice commit). Behavior-changing commits
carry a `Tasks: T68NN` trailer; orchestrator doc/gate commits are marked (ORCH).

## Slice 0 — planning artifacts (ORCH)

- [X] T6800 Author `spec.md` (frozen `CheckpointDatumV1` wire contract), `plan.md`,
      `tasks.md`, and adopt `delegation-boundary-decision.md` (#81 record). Commit:
      `docs(68): freeze CheckpointDatumV1 wire contract spec/plan/tasks`.

## Slice 1 — acceptance harness (PAIR)

- [X] T6801 Create `specs/68-keystate-shape/accept.sh` RED-first: `spec` structural
      target GREEN (asserts the frozen field list, `Threshold` forms, F18 rule
      table, both message domains + literal strings, the seven F10 equalities, the
      Freshness no-sliding-root statement, the #81 no-`delegator` statement); staged
      fail-safe targets (`threshold`,`datum`,`messages`,`vectors`,`aiken`,`parity`,
      `docs`,`final`) RED until their slice; `final` = conjunction.
- [X] T6801b (ORCH) Extend `gate.sh` only if a strict line beyond `just ci` is
      warranted; otherwise leave the existing `accept.sh spec` strict + `final`
      tolerated wiring.

## Slice 2 — Haskell threshold codec (PAIR)

- [X] T6802 `Cardano.KERI.AID.Checkpoint.Threshold`: `Threshold`/`Weight` types,
      `toData`/`fromData`, canonical CBOR, F18 well-formedness (rules 1–14),
      `evaluate`; expose in `cardano-keri.cabal`.
- [X] T6802t Hspec (RED-first): golden (integer m-of-n, single-clause weighted,
      multi-clause weighted, 1-of-1) + one negative per F18 rule 1–14 — with the
      exact `MAX_WEIGHT_DENOM = 2^32` bound (rule 11) and unreduced-rational
      rejection (rule 10) as explicit RED assertions — + **positional-order
      sensitivity** (reordering keys / weights-in-clause / clauses changes
      `keyset_commit`). `accept.sh threshold` GREEN under `just unit`.

## Slice 3 — Haskell datum + messages (PAIR)

- [ ] T6803 `Checkpoint.V1` (`CheckpointDatumV1`, `NextCommitment`, `keyset_commit`,
      `next_digest`, **`deriveAidAssetName`** with frozen `CHECKPOINT_ASSET_DOMAIN_TAG`
      + `0x46 ‖ cesr_aid` preimage) + `Checkpoint.Message` (`InceptionMessage`/
      `AdvanceMessage` builders incl. the frozen `network_id`/`checkpoint_policy_id`/
      `aid_asset_name`/`spent_txid`/`spent_index` context fields + the equalities as
      pure predicates, advance authorized by the **revealed successor set** and
      `aid_asset_name == deriveAidAssetName(cesr_aid)`); cabal exposure.
- [ ] T6803t Hspec (RED-first): datum goldens (1-of-1, m-of-n, weighted,
      multi-clause, witnessed, witnessless); message goldens; the `deriveAidAssetName`
      golden + wrong-code/truncated/mutated-AID/substituted-asset negatives; and
      negatives — **stolen-current-quorum rejection** (full spent-current quorum
      signing the advance), bad `seq_to`, substituted `new_next`, wrong
      `prior_commit`, crossed `cesr_aid`, **cross-`network_id`,
      cross-`checkpoint_policy_id`, cross-`aid_asset_name`, wrong
      `(spent_txid,spent_index)`**, non-increasing `native_sn`, `dip`-registration.
      `accept.sh datum` + `messages` GREEN.

## Slice 4 — generator + committed fixtures (PAIR)

- [ ] T6804 `offchain/app/GenCheckpointVectors.hs` emitting committed JSON
      golden/negative vectors (datum, threshold, messages, **`deriveAidAssetName`**)
      + the Aiken fixtures module from one computation; `just gen-checkpoint-vectors`
      recipe.
- [ ] T6804d Drift check (`regen && git diff --exit-code`); commit the generated
      fixtures. `accept.sh vectors` GREEN.

## Slice 5 — Aiken threshold codec (PAIR)

- [ ] T6805 `onchain/lib/cardano_keri/checkpoint/threshold.ak`: mirrored `Threshold`,
      F18 predicate, `evaluate`.
- [ ] T6805t `threshold_tests.ak`: `cbor.serialise` byte-identity vs fixtures +
      identical verdicts/rejections (RED-first). `aiken check` GREEN; `accept.sh
      aiken` (threshold) GREEN.

## Slice 6 — Aiken datum + messages + parity (PAIR)

- [ ] T6806 `onchain/lib/cardano_keri/checkpoint/{datum,message}.ak`: mirrored
      `CheckpointDatumV1`/`NextCommitment`/messages compiling to the same PlutusData
      + `deriveAidAssetName` (Aiken `blake2b_256` over the same frozen preimage).
- [ ] T6806t Tests: `cbor.serialise` byte-identity vs every datum/message fixture,
      the same derived asset name vs the derivation golden, + identical F10 verdicts.
      `accept.sh parity` GREEN (cross-language byte-identity proven with executable
      evidence).

## Slice 7 — specs reconciliation (PAIR)

- [ ] T6807 Reconcile the transferred draft to the frozen contract in
      `specs/24-keystate/spec.md`, `specs/92-checkpoint-contention/spec.md`, and
      pre-existing `specs/68-keystate-shape/{acdc-zoo,discussion,system-architecture}.md`
      (delegator removed, weighted-threshold survives, `trie_key`/global-trie
      dissolved, current-authority = per-AID checkpoint). `accept.sh docs` (specs
      portion) GREEN; `just ci` GREEN.

## Slice 8 — docs/ reconciliation (PAIR)

- [ ] T6808 Reconcile the transferred draft to the frozen contract in
      `docs/architecture/system.md`, `docs/design/aid-model.md`, `docs/keri-primer.md`,
      `docs/design/vlei.md`, `docs/design/business-cases/{index,regulated-defi}.md`,
      `docs/roadmap.md` (credential-authority-chain vs KERI-delegation distinction;
      roadmap M1 schema / M5 delegated extension; independent-AID-only). Full-docs
      Lychee `--include-fragments` ("Docs links") GREEN; `accept.sh docs` fully GREEN.

## Slice 9 — finalization (ORCH)

- [ ] T6809 Extend `gate.sh` to call `accept.sh final` strictly (remove the `final`
      tolerance); run full `./gate.sh` + Docs-links + `finalization_audit 105 <this
      tasks.md>` GREEN.
- [ ] T6809b `git rm gate.sh` (`chore: drop gate.sh (ready for review)`); push;
      `gh pr ready 105`; write parent handoff (residual risks + exact #77/#79/#81
      closure text + #24 recut). Drop the retained stash after all transferred work
      is committed + verified.

## Traceability (acceptance-target → slice)

- Datum PlutusData shape / tags / order / widths / CBOR (F30) → S3 (HS), S6 (Aiken), S1 (`spec`).
- k/kt/n/nt/witnesses/toad/seq/native_sn/cesr_aid → S3 datum + S1 `spec`.
- Integer + fractional multi-clause thresholds + rejections (F18) → S2 (HS), S5 (Aiken).
- 1-of-1 degenerate as same schema → S2/S3 goldens + S5/S6 parity.
- Inception/advance domains + #77/F10 successor-substitution/replay → S3 + S6.
- Pre-rotation successor-key auth + stolen-quorum reject → S3 (HS) + S6 (Aiken).
- Deployment/token/outref binding + cross-network/policy/asset/outref negatives → S3 + S6.
- `aid_asset_name` pin (`CHECKPOINT_ASSET_DOMAIN_TAG` + `deriveAidAssetName`) + derivation golden/negatives → `spec.md` frozen surface + S3 (HS) + S6 (Aiken) + S4 fixtures + S1 (`spec`).
- Positional weighted semantics + ratified `MAX_WEIGHT_DENOM` → S2 (HS) + S5 (Aiken).
- Freshness vs per-AID UTxO (F12/#79) → `spec.md` Freshness + S7/S8 doc reconciliation.
- #81 no-delegator / `dip`+`drt` reject → `spec.md` + S3 `dip` negative + S7/S8 docs.
- Byte-identical Aiken/Haskell golden + negative vectors → S4 fixtures + S6 `parity`.
- Docs reconciled + #24 recut obligation → S7/S8 + `spec.md` "Downstream obligation".
