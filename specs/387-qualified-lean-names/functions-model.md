# Functions model

Artifact ceiling: 2,000 bytes / 60 lines.

| ID | Function | Signature constraint |
|---|---|---|
| F387-01 | declaration inventory selector | `(LeanSourceMap) -> DeclarationInventory`; select theorem spans from the existing parser without a second identifier regex |
| F387-02 | identity agreement checker | `(expectedIdentities, observedIdentities) -> IdentityAgreement`; reject empty, duplicate, missing, unexpected and same-count-substituted sets |
| F387-03 | theorem-row check | `(SimulatorCore, DeclarationInventory) -> CheckResult`; require exact checker-row and lamp agreement plus one lamp occurrence per declaration |
| F387-04 | falsifier check | `(SimulatorCore, DeclarationInventory, optionalRemovedControl) -> CheckResult`; require every declaration to own a fabricated or structural falsifier and reject foreign falsifiers |
| F387-05 | identity self-controls | `(FrozenInputs, ScratchRoot) -> ControlLedger`; execute dotted-name, same-count-substitution and removed-thing controls with right-reason diagnostics |

Names may follow existing JavaScript style; these rows constrain responsibilities
and observable effects, not local implementation structure.
