# Implementation plan: M1 V1 preprod deployment (#158)

**Branch**: `story/158-preprod-v1-deploy` | **Date**: 2026-07-28  
**Spec**: `specs/158-preprod-v1-deploy/spec.md`

## Summary

Extract the production checkpoint program application into a dedicated
Haskell deployment sublibrary shared by E2E and the new `ckeri` executable.
Add a deterministic manifest model, a `cardano-cli` publisher, and an
independent Koios verifier. Package the binary with Nix, publish all five
reference scripts through the synced preprod node, commit captured facts and
documentation, and make CI re-verify those facts from source.

The operator-selected cheap-team policy is solo Codex implementation with the
ticket `gate.sh` and GitHub CI as reviewers. The PR remains operator-merge
only.

## Technical context

- **Language/toolchain**: GHC 9.12.3, Cabal, haskell.nix.
- **Parser**: `opt-env-conf`; `optparse-applicative` forbidden.
- **Blueprint**: flake-owned fixed-output Aiken `plutus.json`.
- **Ledger**: Conway / Plutus V3.
- **Publisher**: packaged `cardano-cli`, local preprod node socket, payment
  signing key file.
- **Live verifier**: Koios preprod
  `POST /api/v1/reference_script_utxos`.
- **Network**: Cardano preprod, magic `1`.
- **Reference precedent**:
  `/code/amaru-treasury-tx/lib/Amaru/Treasury/Config/OptEnv.hs`.

## Story-shaped surface

```text
offchain/
├── deployment/Cardano/KERI/Deployment/
│   ├── ChainIndex.hs
│   ├── CLI.hs
│   ├── Manifest.hs
│   ├── Publisher.hs
│   └── Script.hs
├── app/Ckeri.hs
├── test/Cardano/KERI/Deployment/ManifestSpec.hs
├── cardano-keri.cabal
└── flake.nix
deploy/preprod/m1-manifest.json
scripts/check-ckeri-cli.sh
.github/workflows/ci.yml
docs/user/m1-preprod-deployment.md
mkdocs.yml
specs/158-preprod-v1-deploy/
├── spec.md
├── plan.md
└── tasks.md
gate.sh
```

## Vertical slices

### Shared V1 derivation and manifest

Move blueprint parsing, UPLC data application, Plutus V3 construction, hash
rendering, and address derivation into the deployment sublibrary. Keep the
legacy E2E module as a compatibility re-export and make
`CheckpointTxBuilder` consume the shared parameter functions.

`Manifest` uses explicit Aeson encoders/decoders so its external schema is
stable. Pure verification compares schema, network, blueprint digest,
parameters, script names/titles/hashes/lengths, checkpoint address, and policy.
Unit tests begin RED with mutated fields, then GREEN against the production
blueprint.

### Uniform `ckeri` configuration

Model the instruction sum with nested `OptEnvConf.commands`:

```text
ckeri
├── deploy
└── manifest
    └── verify
```

Use one `OptEnvConf.setting` per field with explicit option, `CKERI_*`
environment variable, and YAML key. `--config-file` /
`CKERI_CONFIG_FILE` selects the optional YAML input through
`withYamlConfig`. The executable has no second parser.

### Publication

For each derived program, write a temporary `PlutusScriptV3` text envelope.
Query the configured funding address, select its largest plain UTxO, build one
reference output and change, sign, submit, derive the transaction ID, then poll
the independent index for the matching unspent script hash and transaction.

Only after all five references settle does `deploy` assemble and atomically
rename the output manifest. Temporary transaction bodies, signed transactions,
and script envelopes are removed automatically. No secret contents enter
stdout, JSON, or documentation.

### Independent verification

`manifest verify`:

1. decodes and structurally validates the manifest;
2. SHA-256 hashes the immutable blueprint;
3. rebuilds all five applied programs;
4. compares every program fact plus the checkpoint address/policy;
5. runs a read-only `git diff` for the manifest source commit and `onchain/`;
6. POSTs all rebuilt hashes to Koios and matches each exact unspent reference.

The final line is a concise acceptance result suitable for a captured
transcript and CI.

### Reproducible package and CI

Expose the Cabal executable as `packages.ckeri` and `apps.ckeri`. The Nix
runner puts `cardano-cli`, Git, and CA certificates in its strict runtime
environment and supplies the flake-owned blueprint path.

A dedicated CI job checks out full history, builds the binary, asserts parser
surface/forbidden-dependency rules, and runs live verification. The routine
ticket gate invokes the same packaged verifier once the manifest exists.

### Live publication and evidence

Create a dedicated preprod payment key under host secrets, request faucet test
ada, and never copy the key into the repository. Run the packaged command
against `/node/preprod/ipc/node.socket`, capture stdout, then run the packaged
verifier from the clean worktree. Populate docs and PR metadata only from those
captured files.

## Verification and delivery

1. Run pure derivation/manifest tests and controlled negative cases.
2. Build `ckeri`; inspect `--help`, `--env-docs`, and `--config-docs`.
3. Run the full gate before any live transaction.
4. Publish the five preprod references and retain the settled stdout.
5. Run `manifest verify` locally and through the public boundary.
6. Commit the manifest, transcript-backed docs, and CI.
7. Run `./gate.sh` on the exact staged tree and inspect the complete diff.
8. Restore the standing `gate.sh` byte-for-byte, run finalization audit, push,
   mark PR #169 ready, and wait for every GitHub check.
9. Park the ready PR for the operator; do not merge it.

## Risk controls

- No manifest is written until every submitted reference is independently
  visible unspent.
- The verifier trusts rebuilt hashes, not hashes merely read from JSON.
- Exact `txid#index` matching catches moved, spent, or substituted references.
- A full-history checkout makes source-commit verification meaningful in CI.
- The flake-owned blueprint prevents gitignored local `plutus.json` drift.
- Script byte-size tests preserve the stock 16,384-byte transaction boundary.
- Explicit runtime inputs prevent hidden host PATH dependencies.
- All production-host mutations are limited to the dedicated testnet key and
  the explicitly requested preprod transactions.

