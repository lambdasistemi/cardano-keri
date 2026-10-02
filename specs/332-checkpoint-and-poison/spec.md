# Checkpoint, poison, bonds and registry design note

## Reader stories

An identity controller needs to know what stolen current keys can do, how to leave, and what permits return. A hunter needs to know which value pays for advancing or freezing. A consumer developer needs the limits of a checkpoint's authority. A maintainer needs to distinguish the adopted design from the models and validators actually shipped.

## Requirements and invariant contract

All rows are acceptance requirements for this documentation slice. No row claims implementation, proof or on-chain acceptance. Semantic rows require an independent document review; keyword presence is not evidence of correspondence.

| ID | Requirement and failure condition | Severity |
|---|---|---|
| INV-332-STATE | Describe absent, active/present, parked hash without a UTxO, and terminal convicted; no pause, withdraw, on-chain unbonded checkpoint or reap grace window. Distinguish the permanent AID leaf from fresh incarnation tokens. Failure: old Registry lifecycle presented as a ruling. | BLOCKING |
| INV-332-AUTH | Distinguish current quorum poison, witnessed rotation by next keys, new-epoch signed intent for deposit/refund changes and close payee, and permissionless relay/proof submission. Close works while poisoned or frozen; a copied close with changed payee is refused by the checkpoint model. Failure: confuse authority, evidence or destinations. | BLOCKING |
| INV-332-VALUE | Separate conviction bond D_reg, freeze bond B, and advance pool. Explain paid/unpaid rotation and close, signed close premium payee, residual refund, freeze proof and short pool, deposit unfreeze with unchanged juvenility, conviction allocations and no value held by parked leaves. Failure: mix components or call pool funding an admission requirement. | BLOCKING |
| INV-332-REGISTRY | Explain request/batch/plugin boundary, permanent leaf, register/revive evidence, pending leaf updates, and what never touches the registry. Separate current Registry abstractions from the adopted target. Retraction signer remains unresolved; link the existing discussion without restating the debate or choosing policy. | BLOCKING |
| INV-332-LIMITS | State no rollback, no interaction ingestion, delegated-AID exclusion in this slice, witnessless consumer risk, lag/stale-key registration and revival risk, next-key theft, irreversibility of settled actions, abstract cryptographic guards, reserved validity and measured-parameter dependencies. Label modelling assumptions. | BLOCKING |
| INV-332-GAPS | Complete ruling-to-artifact/gap map. Explicitly name open #408 then #358 and checkpoint precedent closed #359; Q-R1/Q-R6 header disagreement is part of that gap. Open #418 owns source-story corrections; use corrected meanings and link the issue while it remains open. Every additional violation of an adopted ruling requires numbered ownership; open design choices are distinguished. | BLOCKING |
| INV-332-SURVIVAL | Describe the tree intended after #319: obsolete enforcement economy and M1.2 record skeleton removed; preserve conviction predicate and decoder before removal, MPF dependency and proof-carrying path. Do not claim deletion already happened or remove adopted freeze/conviction/pool design. | BLOCKING |
| INV-332-READ | Reader stories first; readable lifecycle, value and batching diagrams; decisions and reasons; narrowly supersede historical DN001 and key-compromise material. Curated speech for all changed pages, stamped against exact source. | ADVISORY |
| INV-332-DELIVERY | Strict build, links, presentation on every changed page, diff whitespace, full local CI with attributable baseline, independent semantic review, and exact pushed-head preview bytes. No green/readiness claim from partial gates. | BLOCKING |
| INV-332-FENCE | Only named documentation, speech companions, optional navigation and planning artifacts change. No model/simulator/validator/tooling/dependency edits; no comments, merge or issue filing. | BLOCKING |

## Delivery

One draft PR linked to #332, a source/gap map, gate and review receipts, current CI and served preview identity. Operator acceptance remains external; ticket completion means ready for review, not accepted or merged. The prose must never imply a model proof establishes shipped validator behavior.
