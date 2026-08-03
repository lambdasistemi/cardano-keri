# Close your preprod identity checkpoint

`ckeri close` lets the current KERI controller retire one ACTIVE V1
checkpoint. The transaction spends that exact checkpoint, burns its singleton
AID token, and sends the complete 1,007 tADA escrow to the controller's chosen
Cardano address:

- 2 tADA minimum value;
- 1,000 tADA registration deposit; and
- 5 tADA freeze bond.

There is no successor checkpoint datum or token. Closing one checkpoint does
not revoke the sovereign KERI identifier and does not prevent its controller
from registering again later.

Start with the exported KLI KEL and an ACTIVE checkpoint created as described
in [Register your identity](register-preprod-identity.md).

## Prepare the controller message

The validator requires the current KERI controller keys to authorize a
binary, canonical-CBOR `CloseMessage`. It binds the exact live checkpoint
outref, full refund address, and full refund amount. KERI event signatures do
not authorize that Cardano operation.

Prepare the signing package without access to a Cardano payment key:

```console
$ ckeri close \
    --network preprod \
    --network-magic 1 \
    --aid E... \
    --kel controller.cesr \
    --to addr_test1... \
    --manifest deploy/preprod/m1-manifest.json \
    --signing-package close-package
signing package: close-package/close-message.cbor
preimage sha256: <sha256>
spent checkpoint: <register-txid>#0
refund: 1007 tADA to addr_test1...
```

The package files are mode 0644 because they are intended to cross into an
isolated or offline KLI signer. They contain no private key. Treat the
preimage hash, AID, spent reference, target address, and amount as the signing
review surface.

## Sign with the current KLI controller

Keripy 1.3.5's text-signing command cannot preserve arbitrary binary CBOR.
The repository helper loads the existing KLI habitat and signs the exact
package bytes without exporting the controller's private key:

```console
$ scripts/kli-sign-close.py \
    --name controller \
    --alias controller \
    --package close-package \
    --out controller-signatures.cesr
controller signatures: controller-signatures.cesr
signature count: 1
preimage sha256: <same-sha256>
```

Run the helper in the same Python or container environment as KLI. Supply a
protected keystore's passcode through `KERI_PASSCODE`, never in a command that
will be captured or committed. Prepare a new package if the bound checkpoint
outref changes.

## Submit and verify the refund

Fee funding, collateral, and fee change are separate from the escrow refund.
Use a change address controlled by the payment key; it must differ from the
refund target so the 1,007-tADA output is unambiguous:

```console
$ export CKERI_PAYER=/run/secrets/payment.skey
$ export CKERI_NODE_SOCKET=/node/preprod/ipc/node.socket
$ export CKERI_FUNDING_ADDRESS=addr_test1funding...
$ export CKERI_CHANGE_ADDRESS=addr_test1change...
$ ckeri close \
    --network preprod \
    --network-magic 1 \
    --aid E... \
    --kel controller.cesr \
    --to addr_test1refund... \
    --manifest deploy/preprod/m1-manifest.json \
    --controller-signatures controller-signatures.cesr
close txid: <settled-close-txid>
refunded: 1007 tADA to addr_test1refund...
$ ckeri status --aid E... --backend koios \
    --manifest deploy/preprod/m1-manifest.json \
    --board-manifest deploy/preprod/board-manifest.json
state NOT REGISTERED (closed at <settled-close-txid>) aid E...
```

The command returns only after Koios proves the exact Close burn, spend, and
asset-free full-value refund output. `status` uses the latest mint/burn
history before any temporarily stale ACTIVE UTxO row, so a proved close is
not misreported during index convergence.

All `ckeri` configuration is parsed by `opt-env-conf`. Options, environment
variables such as `CKERI_TO`, `CKERI_KEL`, and `CKERI_CHANGE_ADDRESS`, and
YAML are equivalent; `optparse-applicative` is not used. `KOIOS_TOKEN` is an
optional bearer token with anonymous fallback and is never printed.

## Validator-boundary negative

An unrelated KLI identity cannot close the checkpoint. Normal operation
rejects a non-controller signature locally. The explicit
`--validator-test-non-controller` switch exists only for funded acceptance
testing: it bypasses that local proof and sends the malformed evidence to a
real `cardano-cli transaction build`, where the deployed Plutus V3 spending
validator rejects it.

Do not use that switch in ordinary operation.

## Captured preprod result

The raw `script(1)` plus `tee` artifact is
`deploy/preprod/m1-close-acceptance.txt`. It records the complete
KLI inception → register → ACTIVE status → close prepare → outsider
validator rejection → controller close → closed status journey:

- AID `EN2phEc8LNgyteri4s1aafP2yKuXM83K2qdLyOl9NgWD`;
- premint transaction
  `71a61bd14caee7c0b60158a3bb9d9251bae688faf8cd72552708994735fa21de`;
- registration transaction
  `89dba3d18e407a0a3a9cab0537c455a224039ac4ade2847ce9047c2c8a10f2c7`;
  and
- close transaction
  `f88bb6138da9153818bd543d9ebd548cb09ff221530e936766671f02d1d82392`.

The live run exposed two boundary conditions before the final clean capture:
atomic signing-package files initially inherited mode 0600, and Koios briefly
served a stale ACTIVE UTxO after already indexing a burn. Regression tests
now pin signer-readable package modes and terminal-history precedence.

CI checks the transcript and committed package byte-for-byte, rebuilds
`ckeri`, compares live closed status, and re-queries the three blocks, latest
`-1` asset event, both Close redeemers, exact spent checkpoint, and token-free
1,007-tADA refund. The CI job passes optional `KOIOS_TOKEN` from repository
secrets.
