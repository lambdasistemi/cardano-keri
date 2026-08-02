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

## Why signing has two steps

The native signatures in the KEL cover the exact KERI `rot` event. The
deployed V1 validator separately requires the rotated keys to sign an
`AdvanceMessage` that binds the live Cardano checkpoint outref and successor
state. Substituting the KERI event signatures would be invalid.

Keripy 1.3.5's `kli sign --text @file` opens a text file and UTF-8 re-encodes
it. The canonical-CBOR `AdvanceMessage` is binary, so the stock command cannot
sign those bytes exactly. The repository provides a small KLI-side helper
which uses keripy's own habitat and current verifiers without exporting any
private key:

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

```console
$ export CKERI_PAYER=/run/secrets/payment.skey
$ export CKERI_NODE_SOCKET=/node/preprod/ipc/node.socket
$ export CKERI_FUNDING_ADDRESS=addr_test1...
$ ckeri advance \
    --network preprod \
    --network-magic 1 \
    --aid E... \
    --kel rotation.cesr \
    --manifest deploy/preprod/m1-manifest.json \
    --controller-signatures controller-signatures.cesr
advance txid: <settled-txid>
$ ckeri status --aid E... --backend koios \
    --manifest deploy/preprod/m1-manifest.json \
    --board-manifest deploy/preprod/board-manifest.json
state ACTIVE seq 1 native 1 keys 2-of-5 witnesses 3 (toad 2) bond intact tx <settled-txid>#0
```

Set `KOIOS_TOKEN` for authenticated Koios requests. It is optional, has an
anonymous fallback, and is never printed.

The first advance through a deployment also checks whether the
`observer-advance` reward credential is registered. If absent, `ckeri`
submits and settles a one-time registration certificate through the same
immutable observer reference, then prints its transaction ID before building
the advance. Later controllers reuse that registered credential.

The transaction spends the named ACTIVE checkpoint through the thin
`checkpoint-register` arm and invokes the heavy predicate through a
zero-lovelace `observer-advance` withdrawal. It recreates the complete state
value at the same role address, mints nothing, and uses distinct plain funding
and collateral inputs.

## Validator-boundary evidence

The switches below deliberately bypass client-side completeness checks. They
exist only for funded acceptance testing and still use a real
`cardano-cli transaction build` against the deployed scripts:

- `--validator-test-under-signed` sends one rotated-key signature;
- `--validator-test-under-witnessed` sends one receipt where `toad` is two;
- `--validator-test-stale` replays the already-settled rotation against the
  new live checkpoint.

All three fail at the Plutus V3 `observer-advance` reward script. Without an
explicit test switch, malformed, incomplete, or outref-stale evidence is
rejected locally.

## Captured preprod result

The raw `script(1)` plus `tee` artifact is
`deploy/preprod/m1-advance-acceptance.txt`. It records the complete
inception → register → rotate → prepare → sign → advance → status journey,
including:

- AID `EBLf6spqM8kXCvklb99ObwQUuDzNDOMEne_GFypp52vi`;
- registration transaction
  `f7edc5af3dd3e9777ac07bc8ac0eb771656cd239750361bd991f1b6371372c7e`;
- one-time observer registration
  `c37798c222ff680e44603e8dcd1c990ad6d1a040efdb2fc2a167e707d840ba25`;
- advance transaction
  `ccf10efe3b90833374cf712fdbe2b246f88aadf34c170c9074d16754cdf5c6f2`;
  and
- real validator failures for under-signing, under-witnessing, and stale
  replay.

The capture also preserves two boundary defects encountered during the run:
an unprivileged container could not initially write the signature output, and
the previously unregistered observer account caused the complete transaction
to be rejected at submission. The subsequent captured segments show the
permission correction, the one-time observer registration, and final
settlement; none of those outputs were retyped or removed.

CI byte-checks the committed signing package, re-queries all four settled
transactions through Koios using optional `KOIOS_TOKEN`, and compares
`ckeri status` with the final transcript line.
