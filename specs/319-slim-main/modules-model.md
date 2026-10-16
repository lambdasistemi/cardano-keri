# Module responsibility register

Preservation is released by desk A-004 and epic A-003; gate admission is pending. No implementation bodies are prescribed.

| Module | Responsibility | Dependencies / boundary |
|---|---|---|
| MOD-319-CONVICTION | Retained signed-evidence binding and conviction verdicts in a stable checkpoint library | Depends on retained datum/message/threshold/registration decoding; no dependency on retired settlement modules |
| MOD-319-PARITY | Haskell mirror and generated conviction vectors | Producer remains Haskell; Aiken executes generated cases; retire only deleted behavior |
| MOD-319-CHECKPOINT | Existing checkpoint register/advance/close and surviving migration consumers | Retired arms/parameters go; no new lifecycle design |
| MOD-319-COMPAT | Migration compatibility boundary | Retained compatibility support preserves old-role decoding, authorization and role/payload/value continuity; no ACTIVE-only restriction |
| MOD-319-DEPLOYMENT | Current slim-family script application and manifest generation | Preserves historical schema/source interpretation; never rewrites deployed manifest |
| MOD-319-MPF | Retained proof verification | Uses locked MPF v2.1.0; no dependency on retired skeleton |
| MOD-319-MEASUREMENT | Discover, apply, measure and report surviving scripts/transactions | Uses actual compiler/blueprint, production appliers and ledger serialization/evaluation inputs |

Data and signature contracts live in data-model.md and functions-model.md. No generic framework or new deployment workflow is required.

Retained conviction placement: onchain/lib/cardano_keri/checkpoint/conviction.ak and Cardano.KERI.AID.Checkpoint.Conviction. Retained legacy-state support: onchain/lib/cardano_keri/checkpoint/legacy_state.ak and Cardano.KERI.AID.Checkpoint.LegacyState; reuse the existing Aiken role.ak address responsibility. Lift only the support required by named surviving consumers. Preserve wire data and existing modeled migration behavior.
