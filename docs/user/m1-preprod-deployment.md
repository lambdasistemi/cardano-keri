# The M1 preprod deployment

The M1 V1 checkpoint programs are published as reference scripts on Cardano
preprod. The committed release manifest binds the exact applied programs to
source commit `50a582064ddfde15ebfa3649c6b6fea8d39fc697`, the immutable
blueprint, the deployment parameters, and five settled `txid#index`
references.

This is a testnet release for integration and acceptance. It is not a mainnet
deployment or a production service-level commitment.

## Release identity

| Fact | Value |
| --- | --- |
| Network | `preprod` |
| Network magic | `1` |
| Published at | `2026-07-28T14:37:05Z` |
| Source commit | `50a582064ddfde15ebfa3649c6b6fea8d39fc697` |
| Blueprint SHA-256 | `14ee3f3d5d9617a5cdd13f885477d5ec132d0567e56ea118d1927c7528e587df` |
| Checkpoint policy ID | `0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734` |
| Checkpoint address | `addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822` |

The release applies checkpoint version `0`, network discriminator `0`, a
registration bond of `1,000,000,000` lovelace, a freeze bond of `5,000,000`
lovelace, and a freeze window of `10,000` slots.

## Live reference scripts

Each reference was observed unspent through the public Koios preprod index
before the manifest was written.

| Program | Role | Applied script hash | Settled reference |
| --- | --- | --- | --- |
| `hash-proof` | minting policy | `d767a22b85d0a1c1e2a987b970e990c22c423b2211e788252d28deca` | `5c98bb45cc3e0879a63aa5807dff7f3809ae934ccbcac54f547c189bb4e8701c#0` |
| `observer-lifecycle` | withdrawal observer | `3d18237dc14be14284d775a5766016c7c4c432dedce287011701c6c7` | `c1ebe8b9a69160a04a9e490d4ab1149882f945774fba0cffac2dec7e6886b26f#0` |
| `observer-advance` | withdrawal observer | `50dbbef1c38646d29a1e333337fc5244fe2da3149bf9d5545e5b92c6` | `aaeb5ebe4e9783dc614b8a48634ef7fd9bb517cc0fdc3a4d701a26bd94679734#0` |
| `observer-enforcement` | withdrawal observer | `a35727cf3d64fe3573c9f15fe4ecf408049a8f136ac900d42cf3cc1e` | `2c9c6b3407332d08df895ab0e9e2cf15f7691d9ce24685e4fe8e6e1abb59506d#0` |
| `checkpoint-register` | validator and minting policy | `0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734` | `8a1a404f13b50ec0a266e1427f602916d830b62d757f3ac69976ccba0213c5d1#0` |

The machine-readable facts are in `deploy/preprod/m1-manifest.json`. The
original publication capture is preserved in
`deploy/preprod/m1-acceptance.txt`. The current transaction-path acceptance
capture, `deploy/preprod/m1-board-deploy-verify-acceptance.txt`, performs a
verify-only pass: it compares all five manifest script hashes and references
with live Koios results and confirms the endpoint-board reference and current
catalog without publishing replacement scripts.

## Verify from a checkout

From the repository root at the manifest's source commit, build the
flake-owned binary and verify the release:

```console
$ nix run ./offchain#ckeri -- \
    manifest verify \
    --manifest deploy/preprod/m1-manifest.json \
    --source-repo .
```

`ckeri` hashes the immutable blueprint, rebuilds the five applied scripts,
checks that the checkout's tracked `onchain/` tree matches the manifest source
commit, and queries the independent public chain index. Success ends with:

```text
manifest verify: OK — rebuilt from source; all hashes and on-chain references are live
```

A changed source tree, blueprint, parameter, hash, byte length, transaction
ID, output index, spent reference, or unavailable verification boundary makes
the command fail non-zero.

The checkout must be at source commit
`50a582064ddfde15ebfa3649c6b6fea8d39fc697`. Later on-chain development
deliberately changes the current blueprint, so the standing CI tripwire uses
`scripts/check-m1-manifest-live.sh` to create a detached checkout at that
immutable commit before rebuilding and querying preprod.

## Configuration

`ckeri` uses `opt-env-conf` exclusively. Every operational setting has a
command-line option, a `CKERI_*` environment variable, and a YAML key. The
YAML file itself is selected with `--config-file` or
`CKERI_CONFIG_FILE`. For example:

```yaml
deploy:
  network: preprod
  network-magic: 1
  node-socket: /code/cardano-preprod/ipc/node.socket
  funding-address: addr_test1...
  signing-key-file: /home/operator/.secrets/cardano-keri-preprod/payment.skey
  source-repo: .
  out: deploy/preprod/m1-manifest.json
  timeout-seconds: 1200

manifest:
  verify:
    manifest: deploy/preprod/m1-manifest.json
    source-repo: .
    koios-url: https://preprod.koios.rest/api/v1
```

Set `KOIOS_TOKEN` to send an `Authorization: Bearer` header for either
`deploy` settlement polling or `manifest verify`. The token also has
`--koios-token` and `koios-token` YAML surfaces, but the environment variable
is preferred so the value does not enter shell history or a committed file.
When the setting is absent, `ckeri` deliberately uses anonymous Koios
requests so third parties can verify the release without project secrets.
The repository CI reads `KOIOS_TOKEN` from its encrypted Actions secret.

Run `ckeri deploy --help` or `ckeri manifest verify --help` for the complete
option, environment, and YAML documentation. The payment key is an
operator-side secret; it is read only by `deploy` and never belongs in a
configuration file committed to this repository.

Every mutating command derives the payment address from the signing-key
envelope and requires its payment credential to match the configured funding
address. It enumerates candidate out-refs through Koios, resolves those exact
inputs against the node socket, builds and signs with the Cardano API, submits
through local transaction submission, then waits for the exact effect through
Koios. No external transaction CLI is required. Fragmented funding is valid:
the selector may aggregate several spend inputs while reserving a separate
collateral input.

## Trust and availability boundary

- The source commit and blueprint digest make the release reproducible; they
  do not make later source changes part of this release.
- The deployment submits through a synced preprod node. Verification uses
  Koios as an independent read boundary and fails closed if that boundary is
  unavailable or inconsistent. A Koios token changes API authorization and
  rate limits, not the hashes or chain facts being checked.
- Reference scripts are immutable while their UTxOs remain unspent. Spending
  one makes this manifest fail verification and requires an explicit new
  release.
- The deployment payment key controls only its remaining test ada. It does not
  upgrade or administer the published programs.
- Preprod settlement proves integration behavior, not mainnet economics,
  durability, governance, or decentralization.
