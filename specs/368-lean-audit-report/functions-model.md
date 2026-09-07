# Functions model — #368 hash-bound Lean audit report

Artifact ceiling: 100 lines. These are contract signatures, not implementation
instructions.

## FUN-368-FREEZE

`freezeAuditInput releaseCommit trackedLeanPaths excludedOutputPaths -> AuditedInputManifest | IdentityFailure`

- Enumerates the full tracked extent, binds mode/blob/path, sorts it, and
  returns DAT-368-INPUT plus its SHA-256.

## FUN-368-VERIFY-INPUT

`verifyAuditInput finalTree auditedInputManifest -> ExitStatus`

- Fails on added, missing, mode-changed, or blob-changed audited input and on
  any mismatch among report digest, directory name, manifest, or recomputation.

## FUN-368-AUDIT

`auditLeanFull release inputManifest auditMandate -> AuditReport * EvidencePacket`

- Evaluates all four Lean-auditor surfaces and every frozen finite ledger.
- Returns findings rather than changing a model, theorem, proof, or ruling.

## FUN-368-CHECK-REPORT

`checkAuditReport report evidencePacket invariantSet -> ExitStatus`

- Checks one terminal verdict, seven singular sections, complete matrix
  disposition, evidence integrity, verdict preconditions, and finding shape.

## FUN-368-VERIFY-TRUST

`verifyLeanTrust cleanBuildRoot theoremInventory allowedAxioms -> ExitStatus`

- Builds with no inherited `.lake`, checks source escape hatches, and checks
  each theorem's printed axioms against the licensed set.

## FUN-368-GATE

`gate368 releaseCommit finalCommit frozenGate auditArtifacts -> ExitStatus`

- Reconciles release ancestry, allowed delta, FUN-368-VERIFY-INPUT,
  FUN-368-CHECK-REPORT, FUN-368-VERIFY-TRUST, mutation/correspondence receipts,
  and repository mechanical checks on the exact final commit.
