# Issue 382 functions model

Artifact ceiling: 3,000 bytes / 80 lines.

| ID | Function | Signature-level contract |
|---|---|---|
| F382-01 | `classifySubmissionRejection` | `(rawDiagnostic : ByteString) -> SubmissionRejection`; recognizes `OutsideValidityIntervalUTxO` exactly and classifies every other value as domain rejection |
| F382-02 | `submitWithValidityRecovery` | `(environment : CheckpointEnv, label : String, buildFresh : IO ConwayTx) -> IO TxId`; submits attempt 1, invokes `buildFresh` once more only after F382-01 returns validity expiry, and never resubmits the expired transaction |
| F382-03 | `emitSubmissionVerdict` | `(label : String, attempt : Int, rejection : SubmissionRejection, finalState : FinalState) -> IO ()`; produces stable timing/domain-specific output including the scenario label |
| F382-04 | `withInjectedSubmitDelay` | `(delaySlots : Natural, action : IO a) -> IO a`; test-only bounded delay used by one named live control; 25 slots is observable in its receipt |
| F382-05 | `validityRaceControl` | `(environment : CheckpointEnv) -> IO ControlReceipt`; reaches the real submitter, proves first-attempt expiry and one fresh successful retry |
| F382-06 | `domainNoRetryControl` | `(environment : CheckpointEnv) -> IO ControlReceipt`; reaches a genuine non-expiry refusal and proves one submission and zero rebuilds |

Names may be adapted to the existing E2E module vocabulary, but the explicit
arguments, result distinctions, retry cardinality, and effects above are fixed.
