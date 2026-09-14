# Functions model

Artifact ceiling: 2,000 bytes / 60 lines.

| ID | Function | Signature constraint |
|---|---|---|
| F387-01 | declaration inventory selector | `(LeanSourceMap) -> DeclarationInventory`; select theorem spans from the existing parser without a second identifier regex |
| F387-02 | identity classifier | `(StepSourceMap, DeclarationInventory) -> { observable, proofOnly, inversionDenominator }`; derive constructor names and admit only matching `Step.<constructor>_iff`; assert disjoint/exhaustive classes |
| F387-03 | class agreement checker | `(SimulatorCore, ClassifiedInventory) -> CheckResult`; require exact checker-row/lamp/falsifier agreement and one lamp for each observable identity, plus exact proof-only/inversion-denominator agreement |
| F387-04 | identity agreement primitive | `(expectedIdentities, observedIdentities) -> IdentityAgreement`; reject empty, duplicate, missing, unexpected and same-count-substituted sets |
| F387-05 | identity self-controls | `(FrozenInputs, ScratchRoot) -> ControlLedger`; execute dotted discovery, both substitution classes, inversion removal, invalid proof-only entry and retained removed-thing controls with right-reason diagnostics |

Names may follow existing JavaScript style; these rows constrain responsibilities
and observable effects, not local implementation structure.
