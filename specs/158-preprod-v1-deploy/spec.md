# Feature specification: M1 V1 preprod deployment (#158)

**Feature branch**: `story/158-preprod-v1-deploy`  
**Created**: 2026-07-28  
**Status**: Approved for implementation  
**Issue**: https://github.com/lambdasistemi/cardano-keri/issues/158  
**Parent**: producer applications epic #156, milestone M1

## User scenarios

### User Story 1 — Publish V1 with `ckeri` (P1)

An operator runs:

```console
ckeri deploy --network preprod --out deploy/preprod/m1-manifest.json
```

The command derives the complete applied checkpoint script set from the
repository-owned production blueprint, publishes one reference-script UTxO per
program, waits for settlement, writes the manifest, and prints every script
hash and `txid#index`.

**Independent proof**: start with a funded preprod payment key, invoke only
`ckeri deploy`, and observe five live unspent reference-script UTxOs whose
script hashes equal the command output and manifest.

### User Story 2 — Rebuild and verify the release (P1)

A stranger checks out the repository and runs:

```console
ckeri manifest verify --manifest deploy/preprod/m1-manifest.json
```

The command rebuilds all five applied programs from the immutable Aiken
blueprint, checks their hashes and the source provenance in the manifest, and
checks every exact reference against preprod.

**Independent proof**: the command prints that the source rebuild, all hashes,
and all on-chain references are OK. Mutating one hash, parameter, source
commit, blueprint byte, transaction ID, or output index makes it fail
non-zero.

### User Story 3 — Configure one binary uniformly (P1)

An operator can supply every `ckeri` setting by command-line option,
environment variable, or YAML key. A selected YAML file is itself configured
with an option or environment variable.

**Independent proof**: parser documentation and black-box checks show the
same operational fields on all three surfaces. The Cabal plan and Haskell
imports contain `opt-env-conf` and contain no `optparse-applicative` or
`Options.Applicative`.

## Functional requirements

- **FR-001**: The repository MUST build an executable named `ckeri`.
- **FR-002**: Its initial command paths MUST be exactly `deploy` and
  `manifest verify`.
- **FR-003**: `ckeri` MUST use `opt-env-conf` for arguments, environment
  variables, and YAML configuration. `optparse-applicative` is forbidden.
- **FR-004**: The parser pattern MUST follow the local
  `/code/amaru-treasury-tx` `OptEnvConf` precedent.
- **FR-005**: The V1 release MUST derive these five Plutus V3 programs:
  `hash-proof`, `observer-lifecycle`, `observer-advance`,
  `observer-enforcement`, and `checkpoint-register`.
- **FR-006**: Derivation MUST use the production constants already exercised
  by E2E: version `0`, network discriminator `0`, registration bond
  `1_000_000_000`, freeze bond `5_000_000`, freeze window `10_000`.
- **FR-007**: The applied script derivation MUST be shared with the E2E path,
  not independently reimplemented in the CLI.
- **FR-008**: `deploy` MUST publish each applied program as a preprod
  reference script, sign only through a configured key file, and wait until
  every submitted output is observable unspent before writing the manifest.
- **FR-009**: A partial or failed publication MUST NOT replace the requested
  manifest.
- **FR-010**: The manifest MUST pin schema, network/magic, source repository
  and commit, blueprint SHA-256, application parameters, checkpoint address
  and policy ID, publication time, and every script's title/hash/byte
  length/reference.
- **FR-011**: Manifest JSON MUST be deterministic apart from captured
  publication facts.
- **FR-012**: `manifest verify` MUST load the configured immutable blueprint,
  rebuild the five applied programs, and compare every hash and byte length.
- **FR-013**: Verification MUST prove the configured checkout's tracked
  `onchain/` tree matches the manifest source commit.
- **FR-014**: Verification MUST query an independent preprod chain index and
  require each exact `txid#index` to remain an unspent reference-script UTxO
  for the declared rebuilt hash.
- **FR-015**: Successful `deploy` output MUST print all five settled references.
- **FR-016**: Successful verification output MUST explicitly report the
  source rebuild, all hashes, and all on-chain references as OK.
- **FR-017**: A Nix package/app MUST carry `ckeri` and its explicit runtime
  tools, including `cardano-cli`.
- **FR-018**: CI MUST build `ckeri` and run live verification of the committed
  preprod manifest.
- **FR-019**: The repository MUST add a navigable page titled “The M1 preprod
  deployment” with operator commands, all settled transaction IDs, the
  verifier result, and trust/availability boundaries. The raw successful
  transcript belongs in the captured acceptance artifact and PR body.
- **FR-020**: The full repository gate and all GitHub checks MUST be green
  before the PR is parked for operator merge.
- **FR-021**: The PR body MUST embed the byte-for-byte `script(1)` or
  `tee`-captured full vertical acceptance journey, with literal `$` commands,
  command output, all settled transaction IDs, and the story's final
  `manifest verify` result. CI MUST match that capture to the manifest; a
  retyped or narrative substitute is not acceptance evidence.
- **FR-022**: `deploy` and `manifest verify` MUST accept an optional Koios
  bearer token through the shared `KOIOS_TOKEN` opt-env-conf environment
  setting (plus option and YAML surfaces), set the `Authorization` header when
  present, and retain anonymous verification when absent. The M1 manifest CI
  job MUST inject the repository `KOIOS_TOKEN` secret.

## Key entities

- **Applied script**: the final Plutus V3 program after all release parameters
  are applied; its ledger hash is what the manifest and live reference carry.
- **Reference-script UTxO**: an unspent Cardano output whose reference-script
  field contains an applied V1 program.
- **Release manifest**: the committed JSON binding source, blueprint,
  parameters, hashes, addresses, and exact preprod references.
- **Source commit**: the latest commit whose tracked `onchain/` tree is exactly
  the one from which the release blueprint is built.

## Success criteria

- **SC-001**: `ckeri deploy` settles five distinct V1 preprod references and
  prints the same facts committed in the manifest.
- **SC-002**: `ckeri manifest verify` independently rebuilds and validates all
  five scripts plus all five exact unspent references.
- **SC-003**: Controlled negative tests fail for manifest, blueprint, source,
  and live-reference drift.
- **SC-004**: CLI help/config documentation exposes option, environment, and
  YAML names for every operational setting, with no forbidden parser.
- **SC-005**: The PR contains the raw captured source → `deploy` → `manifest
  verify` transcript and settled transaction IDs, while the docs provide the
  navigable narrative and operator guidance.
- **SC-006**: Strict docs, local `./gate.sh`, and GitHub CI exit zero; draft PR
  #169 becomes ready and remains unmerged for the operator.
- **SC-007**: Request tests prove the bearer header is exact when configured
  and absent when no token is configured; CLI help exposes `KOIOS_TOKEN` on
  both command paths.

## Assumptions and boundaries

- V1 is deliberately preprod-only. Mainnet deployment is outside this story.
- The repository's flake-owned `plutus-blueprint` is the immutable production
  blueprint input.
- `ckeri` may drive the official `cardano-cli` as a packaged runtime tool; it
  must not depend on shell configuration or an untracked parser wrapper.
- Koios preprod's unspent reference-script query is the independent public
  verification boundary. The deployment itself submits through the configured
  local node socket.
- Koios authentication is optional and must never be printed. CI uses its
  repository secret; public verifiers require no token.
- The payment signing key and faucet funding are host-side operator material.
  The key is never logged or committed.
- `kli` continues to own every KERI operation. This story adds only Cardano
  release publication and verification.
- Witness-host IaC follow-up from #157 is explicitly outside this story.
- Raw full-journey acceptance evidence is cumulative for every application
  story from #158 onward; later stories must capture the entire preceding
  vertical journey through their own final verb.
