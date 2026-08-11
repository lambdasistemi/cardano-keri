# Functions model — #263 reproducible endpoint-board validator

Artifact ceiling: 5,000 bytes and 130 lines.

No new production transaction API is required. Existing production blueprint
loading and board derivation remain the executable authority.

## Existing production functions

- **FUN-263-LOAD:** `loadBlueprint artifactPath -> IO Blueprint`
- **FUN-263-DERIVE:** `deriveBoardScript blueprint -> Either String ScriptArtifact`
- **FUN-263-CONSUME:** `consumerErrors manifest derivedArtifact -> [String]`

Constraints:

- `FUN-263-DERIVE` selects the exact validator title and derives policy from
  compiled bytes;
- malformed or ambiguous selection is an error;
- `FUN-263-CONSUME` continues to require exact frozen-policy equality and is
  unchanged by this ticket.

## Runner binding

- **FUN-263-BOARD-BINDING:** `boardArtifactPath -> deployment/local-write test process`

Constraints:

- the board path is repository-owned and required;
- it is separate from the current checkpoint blueprint path;
- no current-blueprint, provider, or remote fallback exists.

## Permanent proof behavior

- **FUN-263-IDENTITY-CHECK:**
  `artifactPath -> Either Failure VerifiedBoardIdentity`
- **FUN-263-MANIFEST-CHECK:**
  `manifest -> artifactPath -> Either [String] ScriptArtifact`

`VerifiedBoardIdentity` contains the exact title, decoded length, recomputed
program SHA-256, and production-derived policy. Success requires equality with
all frozen constants, not merely self-consistency inside the artifact.

## Board write proofs

- **FUN-263-POST-PROOF:**
  `boardArtifact -> localSnapshot -> Either BuildError BuiltPost`
- **FUN-263-UPDATE-PROOF:**
  `boardArtifact -> localSnapshot -> Either BuildError BuiltUpdate`
- **FUN-263-RETIRE-PROOF:**
  `boardArtifact -> localSnapshot -> Either BuildError BuiltRetire`

Constraints:

- each proof uses the exact recovered reference script;
- each observes the complete expected local read set and one snapshot through
  the #240/#262 harness;
- no provider access or post-submit live observation is part of these proof
  functions.

Names for test-only helpers may follow existing conventions; the input,
authority, and fail-closed relationships above are fixed.
