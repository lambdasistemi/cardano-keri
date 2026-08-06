# Rotate your preprod identity

`ckeri advance` projects a witnessed KLI rotation into an existing V1
checkpoint. It consumes the ACTIVE output, preserves its complete
1,007-tADA value and singleton AID token, and writes the rotated keys and
witness state at sequence plus one.

Start with a registered identity from
[Register your identity](register-preprod-identity.md). The M1 reference
journey uses five current and next KERI keys, threshold two, three witnesses,
and witness threshold two.

## Rotate and export with KLI

Rotate in the controller's ordinary KLI environment and wait for the witness
receipts:

```console
$ kli rotate \
    --name org \
    --alias org \
    --next-count 5 \
    --isith 2 \
    --nsith 2 \
    --toad 2 \
    --receipt-endpoint
$ kli status --name org --alias org
Seq No: 1
Witnesses:
Count: 3
Receipts: 3
Threshold: 2
$ kli export --name org --alias org > rotation.cesr
```

`ckeri` verifies the full inception-plus-rotation stream: event framing,
lineage, native sequence, old next-key commitments, KERI event signatures,
witness delta, incoming witness set, and receipt threshold.

## Authorization and the immutable M1 release

Newer source implements permissionless advance using the native KERI `rot`
event signatures. The immutable M1 preprod reference script predates that
change: it still verifies the legacy Cardano-domain `AdvanceMessage`. This is
release skew, not a different transaction-submission path. Never infer the
deployed validator contract solely from a newer checkout.

For this frozen release, prepare and sign that legacy package:

```console
$ ckeri advance \
    --network preprod \
    --network-magic 1 \
    --aid E... \
    --kel rotation.cesr \
    --manifest deploy/preprod/m1-manifest.json \
    --signing-package advance-package
signing package: advance-package/advance-message.cbor
preimage sha256: <sha256>
spent checkpoint: <txid>#<index>
$ scripts/kli-sign-advance.py \
    --name org \
    --alias org \
    --package advance-package \
    --out controller-signatures.cesr
controller signatures: controller-signatures.cesr
signature count: 5
preimage sha256: <same-sha256>
```

Run the helper in the same Python/container environment as KLI. If the
keystore is passcode-protected, supply it through `KERI_PASSCODE`; do not put
the passcode in a captured command or committed file. The helper checks the
package schema, AID, filename, and SHA-256 before signing the binary bytes.

The package is bound to one live checkpoint outref. Prepare it again if that
outref changes.

## Settle the advance

All `ckeri` settings use `opt-env-conf`; options, environment variables, and
YAML are equivalent. `optparse-applicative` is not used.

The CLI requires `--controller-signatures FILE` for submission (or
`--signing-package DIR` to prepare the package). For the immutable M1 release,
the file is produced by `scripts/kli-sign-advance.py` over
`advance-message.cbor`.

```console
$ export CKERI_PAYER=/home/operator/.secrets/cardano-keri-preprod/payment.skey
$ export CKERI_NODE_SOCKET=/code/cardano-preprod/ipc/node.socket
$ export CKERI_FUNDING_ADDRESS=addr_test1...
$ ckeri advance \
    --network preprod \
    --network-magic 1 \
    --aid E... \
    --kel rotation.cesr \
    --manifest deploy/preprod/m1-manifest.json \
    --controller-signatures controller-signatures.cesr \
    --validator-test-under-signed
advance txid: <settled-txid>
$ ckeri status --aid E... --backend koios \
    --manifest deploy/preprod/m1-manifest.json \
    --board-manifest deploy/preprod/board-manifest.json
state ACTIVE seq 1 native 1 keys 2-of-5 witnesses 3 (toad 2) bond intact tx <settled-txid>#0
```

Set `KOIOS_TOKEN` for authenticated Koios requests. It is optional, has an
anonymous fallback, and is never printed.

The `--validator-test-under-signed` spelling is acceptance-only. In this exact
1-of-1 M1 compatibility journey it bypasses the newer local native-event rule;
the immutable on-chain observer still evaluates and accepts the legacy
signature. Do not generalize this escape hatch to a newer deployment.

The first advance through a deployment also checks whether the
`observer-advance` reward credential is registered. If absent, `ckeri`
submits and settles a one-time registration certificate through the same
immutable observer reference, then prints its transaction ID before building
the advance. Later controllers reuse that registered credential.

The transaction spends the named ACTIVE checkpoint through the thin
`checkpoint-register` arm and invokes the heavy predicate through a
zero-lovelace `observer-advance` withdrawal. It recreates the complete state
value at the same role address, mints nothing, and uses distinct plain funding
and collateral inputs. Exact candidate out-refs come from Koios, are resolved
through N2C, and the signed transaction is submitted through local transaction
submission without a subprocess.

## Validator-boundary evidence

The switches below deliberately bypass client-side completeness checks. They
exist only for funded acceptance testing and still send the transaction to
real deployed-script evaluation through the node:

- `--validator-test-under-signed` sends one rotated-key signature;
- `--validator-test-under-witnessed` sends one receipt where `toad` is two;
- `--validator-test-stale` replays the already-settled rotation against the
  new live checkpoint.

All three fail at the Plutus V3 `observer-advance` reward script. Without an
explicit test switch, malformed, incomplete, or outref-stale evidence is
rejected locally.

## Captured preprod result

The mechanical artifact is
`deploy/preprod/m1-advance-acceptance.txt`. It records the complete
rotate → prepare → legacy-sign → in-process advance → status journey for the
registration documented above, including:

- AID `EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P`;
- predecessor registration
  `6ecc2e0729347f5008a4f07ba18c2ce6ad745ace4911818b838037dfc83241e2`;
- advance transaction
  `f0f3a18ff994f5865b638dab33e166b8baa9996eb58d1691f0d26c8b218bfe4a`;
  and
- the exact package digest and matching controller signature.

That primary AID is 1-of-1. Its acceptance-only
`--validator-test-under-signed` invocation is the successful immutable-M1
compatibility override described above, not an under-signed negative control.
The separate
`deploy/preprod/m1-advance-historical-negative-acceptance.txt` capture uses a
2-of-5 controller with three witnesses and threshold two. Its under-signed,
under-witnessed, and stale attempts each reach the deployed Plutus evaluator
and fail. The transcript checker requires all three failures independently.
