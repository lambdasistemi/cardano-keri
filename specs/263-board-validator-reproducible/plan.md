# Implementation plan — #263 reproducible endpoint-board validator

Artifact ceiling: 6,000 bytes and 150 lines.

## Durable design decision

Recover and retain the deployed program as a compact, board-specific
preproduction blueprint artifact under `deploy/preprod/`, rather than pinning
the whole 581,696-byte historical multi-validator blueprint or weakening the
frozen manifest.

The compact artifact contains only the production-compatible blueprint fields
needed by `loadBlueprint` and `deriveBoardScript`, plus provenance metadata.
Its program bytes are authoritative because three independent observations
meet: historical fixed-output blueprint digest, program SHA-256, and derived
Cardano policy ID. The current source-built blueprint remains separate.

## Strategy

One OWNER behavior slice keeps artifact recovery, binding, manifest proof, and
the three #240 board-verb proofs indivisible. A partial commit would either
introduce an unconsumed artifact or leave the known production mismatch
parked.

1. Extract only `endpoint_board.endpoint_board.mint` and its exact compiled
   program from the byte-reproduced historical blueprint into a repository
   artifact, recording all provenance fields from **DAT-263-ARTIFACT**.
2. Add a distinct board-artifact binding in the Nix test runners; do not reuse
   or replace `KERI_CHECKPOINT_BLUEPRINT`.
3. Make the manifest test load the board binding, remove its pending marker,
   and assert production derivation equals the frozen manifest.
4. Seed post/update/retire reference outputs with the recovered script and
   replace #240's residual cases with complete local read-set/build proofs.
5. Add the lasting identity/provenance proof, demonstrate nibble-perturbation
   RED and restored GREEN, then run the frozen ticket gate.

## Path fences

Owned behavior/proof paths:

- `deploy/preprod/endpoint-board-blueprint.json` (new exact artifact);
- `offchain/flake.nix` (board-specific test binding only);
- `offchain/deployment-test/Cardano/KERI/Deployment/ManifestSpec.hs`;
- `offchain/query-test/Cardano/KERI/Indexer/LocalWritePathSpec.hs`;
- the smallest cabal/Just test registration surface needed for the permanent
  identity check, if an existing test target cannot host it.

Forbidden paths:

- `onchain/**` source and blueprint output;
- `offchain/deployment/Cardano/KERI/Deployment/EndpointBoardManifest.hs`;
- unrelated production composition/interpreter modules;
- `docs/**`, dependency versions, lock files, and generated build output.

## Constraints

- Base remains exact commit `085367270536afc175ed9628d6992263145ce903`
  while predecessor PR #264 is open; do not rebase during the campaign.
- Build budget is 10, with 4 additional runs reserved only for auditor
  findings. Historical byte reproduction consumed build 1.
- Every charged gate includes `ci-onchain`; all Nix invocations use
  `--no-write-lock-file`.
- Aiken diagnostics requiring terminal behavior run under `script -qec`.
- No live-chain action, force push, generated blueprint replacement, or
  production-policy change is permitted.

## Verification

- permanent exact-byte/digest/policy derivation check;
- retained perturbation RED and restored-GREEN receipt;
- executing manifest and board post/update/retire focused suites;
- unchanged `consumerErrors` tree diff and exact equality check;
- `ci-onchain`, offchain CI, format, hlint, path-fence, commit, task, and final
  audited-tree verification within budget.

## Artifact measurements

| Artifact | Bytes | Lines | Ceiling |
| --- | ---: | ---: | --- |
| `spec.md` | 3,951 | 81 | 6,000 / 150 |
| `plan.md` | 3,829 | 85 | 6,000 / 150 |
| `modules-model.md` | 2,930 | 69 | 5,000 / 130 |
| `data-model.md` | 2,935 | 71 | 5,000 / 130 |
| `functions-model.md` | 2,211 | 61 | 5,000 / 130 |
| `tasks.md` | 2,147 | 39 | 5,000 / 140 |
