# Issue 383 functions model

Artifact ceiling: 2,500 bytes / 70 lines.

| ID | Function | Signature-level contract |
|---|---|---|
| F383-01 | `freezeSubject` | `(referenceCommit, currentCommit, trackedExtent) -> SubjectManifest | IdentityFailure`; enumerate, sort and require byte equality for every campaign-subject path |
| F383-02 | `freezeGateV6` | `(gateV5, line23CommentAuthority) -> GateIdentity`; preserve v5 and require exactly one inserted comment byte in v6 |
| F383-03 | `runLegControls` | `(gateV6, controlLedger, disposableRoot) -> ControlResults`; execute every negative control without modifying frozen inputs or spending a full campaign |
| F383-04 | `runGateV6Once` | `(gateV6, sourceTree, campaignRoot, budget210) -> CampaignEvidence`; execute every gate leg once and retain complete output |
| F383-05 | `verifyCampaign` | `(CampaignEvidence, expectedIdentity, expectedTotals) -> ExitStatus`; require all conjunctive R383-05 outcomes and exact v6 path/hash |
| F383-06 | `verifyRetention` | `(campaign030, frozenHashes) -> ExitStatus`; prove historical bytes unchanged without promoting them to the new run |
| F383-07 | `auditSubmission` | `(candidate, gateV6, controls, historicalEvidence, newEvidence) -> AuditResult`; independently settle every invariant without another full campaign |

Names may follow existing shell conventions. No function may rewrite a frozen
campaign-subject path or convert a missing execution into PASS.
