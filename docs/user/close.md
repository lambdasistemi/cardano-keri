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
$ export CKERI_PAYER=/home/operator/.secrets/cardano-keri-preprod/payment.skey
$ export CKERI_NODE_SOCKET=/code/cardano-preprod/ipc/node.socket
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
testing: it bypasses that local proof and sends the malformed evidence through
local transaction submission, where the deployed Plutus V3 spending validator
rejects it.

Do not use that switch in ordinary operation.

## Captured preprod result

The mechanical artifact is
`deploy/preprod/m1-close-acceptance.txt`. It records the complete ACTIVE
status → close prepare → controller sign → in-process close → closed status
journey:

- AID `EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P`;
- predecessor advance
  `f0f3a18ff994f5865b638dab33e166b8baa9996eb58d1691f0d26c8b218bfe4a`;
- exact 1,007-tADA refund to the configured payment-credential base address;
  and
- close transaction
  `8bb6d5e61b1ffaf69d1a7c8f4ffe53182aa4963a4d5c360c6356bbe14439abd5`.

The checker verifies chronology, package/signature digest agreement, exact
refund amount and address, and terminal `NOT REGISTERED` status. With a live
binary configured it also re-queries settlement through Koios.

The controller happy path is intentionally separate from
`deploy/preprod/m1-close-historical-negative-acceptance.txt`, where an
unrelated KLI identity signs the close package and the deployed spending
validator rejects it. The checker requires that failure before the later
controller-signed close.
