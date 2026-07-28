# Register your identity on preprod

`ckeri register` turns a standard keripy inception export into a funded V1
checkpoint on Cardano preprod. It does not create, rotate, or store KERI keys:
the controller remains sovereign and `ckeri` consumes only the CESR bytes from
`kli export`.

This M1 flow needs:

- keripy 1.3.5 `kli`;
- the packaged `ckeri` binary and the committed
  `deploy/preprod/m1-manifest.json`;
- a synced preprod node socket and payment signing key; and
- at least 1,007 tADA plus transaction fees and a separate collateral UTxO.

The ACTIVE output carries 2 tADA minimum value, the 1,000 tADA registration
deposit, and the 5 tADA freeze bond.

## Export a KLI identity

Create and export the identity with KLI. An unwitnessed 1-of-1 example is:

```console
$ kli init --name stranger --nopasscode
$ kli incept \
    --name stranger \
    --alias stranger \
    --transferable \
    --icount 1 \
    --isith 1 \
    --ncount 1 \
    --nsith 1 \
    --toad 0
$ kli export --name stranger --alias stranger > stranger.cesr
```

For a witnessed 2-of-5 organization, resolve the selected witness OOBIs before
cutting keys, then use five current and next keys with signing threshold two:

```console
$ kli oobi resolve --name org --oobi https://witness-1.preprod.plutimus.com/oobi/BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI/controller --oobi-alias witness-1
$ kli oobi resolve --name org --oobi https://witness-2.preprod.plutimus.com/oobi/BBkK9o9mMm_nIu5yl3x3L7ti8cYoKg-AoxpqQapMcE5B/controller --oobi-alias witness-2
$ kli oobi resolve --name org --oobi https://witness-3.preprod.plutimus.com/oobi/BNP31dFWbqS_oUe2CUu24Ct7cQjpk3DscLzbpGT5OEz4/controller --oobi-alias witness-3
$ kli incept \
    --name org \
    --alias org \
    --transferable \
    --icount 5 \
    --isith 2 \
    --ncount 5 \
    --nsith 2 \
    --wits BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI \
    --wits BBkK9o9mMm_nIu5yl3x3L7ti8cYoKg-AoxpqQapMcE5B \
    --wits BNP31dFWbqS_oUe2CUu24Ct7cQjpk3DscLzbpGT5OEz4 \
    --toad 2
$ kli export --name org --alias org > org.cesr
```

Story #165 will add the board command that discovers and health-probes
witnesses before inception. Until then, `ckeri register` refuses a witnessed
KEL by default. Pass `--allow-unlisted-witnesses` only after accepting that
the witnesses have no live board-membership check and therefore reduced
public watchability. Witness selection remains an off-chain controller
policy; the validator does not impose a witness board.

## Register and inspect

All configuration is parsed by `opt-env-conf`. Command-line options,
environment variables, and YAML are equivalent surfaces; the implementation
does not use `optparse-applicative`. This environment-based invocation keeps
the operational paths explicit:

```console
$ export CKERI_NETWORK=preprod
$ export CKERI_NETWORK_MAGIC=1
$ export CKERI_KEL="$PWD/stranger.cesr"
$ export CKERI_PAYER=/run/secrets/payment.skey
$ export CKERI_NODE_SOCKET=/node/preprod/ipc/node.socket
$ export CKERI_FUNDING_ADDRESS=addr_test1...
$ export CKERI_MANIFEST="$PWD/deploy/preprod/m1-manifest.json"
$ ckeri register
premint txid: <settled-hash-proof-txid>
register txid: <settled-checkpoint-txid>
escrow: 1007 tADA (min 2 + D 1000 + B 5)
$ ckeri status E...
state ACTIVE seq 0 native 0 keys 1-of-1 witnesses 0 (toad 0) bond intact tx <txid>#0
```

Set `KOIOS_TOKEN` when authenticated Koios access is available. It is optional:
anonymous status and settlement polling remain available to third parties.
The token is read through `opt-env-conf` and is never printed in diagnostics.

`register` first mints a one-shot hash proof, waits for that exact asset and
transaction, then burns it while minting the AID checkpoint token. `status`
queries that exact token and fails closed unless the address, singleton
quantity, inline V1 datum, AID, and 1,007 tADA escrow all agree.

## Failure and repeat semantics

An ACTIVE output below 1,007 tADA is rejected by the deployed checkpoint
validator during `cardano-cli transaction build`; this is not a client-side
balance heuristic. The acceptance transcript records the real Plutus V3
evaluation failure.

The ledger deliberately has no global AID-unicity rule. Every controller is
free to register another fully funded checkpoint copy, including after a
conviction. `ckeri register` nevertheless refuses an already-live AID by
default to prevent accidental duplicate escrows. The explicit
`--allow-existing-checkpoint` override submits another valid copy and prints
the residual warning. Once two copies exist, `ckeri status` reports an
ambiguous checkpoint set instead of pretending there is one canonical output.

The unedited script(1)+tee capture is committed at
`deploy/preprod/m1-register-acceptance.txt`. It contains fresh 1-of-1 and
witnessed 2-of-5 KLI journeys, the underfunded validator rejection, the
default duplicate and unlisted-witness refusals, the explicit repeat, and all
six settled premint/register transaction IDs. CI checks the transcript shape,
re-queries all six transactions, and compares the final witnessed status to
the live chain.
