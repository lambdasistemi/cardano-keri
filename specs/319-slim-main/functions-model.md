# Changed signature register

Gate admission pending. Existing compatibility interfaces move without changing their types or behavior.

| Function | Argument names and types | Result / constraint |
|---|---|---|
| convict_predicate | tip: CheckpointDatumV1; evidence: EventEvidence | ConvictVerdict, unchanged ordered behavior in retained library |
| bind_enforcement_evidence | aid: ByteArray; evidence: EnforcementEvidence | EnforcementBindingVerdict, unchanged ordered EE0–EE9 binding |
| convictPredicate | d: CheckpointDatumV1; e: EventEvidence | Either ConvictError (), unchanged in Cardano.KERI.AID.Checkpoint.Conviction |
| bindEnforcementEvidence | aid: CesrAid; e: EnforcementEvidence | Either EnforcementBindingError EventEvidence, unchanged in the retained conviction module |
| checkpoint_register | Existing migration_hash, lifecycle_hash, advance_hash, network_id, d_reg; remove enforcement_hash, entitlement_hash, freeze_bond, freeze_window | Remaining parameters applied in actual compiled declaration order |
| Current candidate manifest derivation | Existing Blueprint and release inputs, narrowed to surviving family | Distinct from interpretation of recorded historical deployment |
| Measurement command | Exact candidate/source, parameter/input and toolchain identities | Nonempty complete machine-readable report and PR table; nonzero on mismatch/missing path/ledger violation |

No bodies, algorithms, fixtures or tests are prescribed here. Compatibility support owns the lifted old-role types/helpers with unchanged wire encodings and behavior. No guessed downstream economic parameters are accepted.
