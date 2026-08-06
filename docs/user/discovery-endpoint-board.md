# Discovery — the endpoint board

The endpoint board is a public, current OOBI catalog on Cardano preprod. A
witness publishes its own KERI-signed `/loc/scheme` reply. Anyone can then find
the record from the chain, verify its KERI SAID and Ed25519 signature, and dial
the advertised endpoint without receiving a private `witnesses.json` file.

The chain contributes availability and currency, not trust. The witness signs
the endpoint record; `ckeri board list` verifies that signature and the KERI
record semantics. The current catalog is exactly the unspent set at the frozen
board address.

## Public release facts

The M1 board contract is:

- policy id
  `54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c`;
- preprod address
  `addr_test1wp2yjnu2rv5nqfqm0w06qy8kruk0vvra42l6k600h7gjzrqpd4hm4`;
- datum schema
  [`specs/165-endpoint-board/datum-schema.md`](https://github.com/lambdasistemi/cardano-keri/blob/bb26876cb81c2fb268b95baf7889bb17a57edf3f/specs/165-endpoint-board/datum-schema.md);
  and
- deployment locator `deploy/preprod/board-manifest.json`.

The manifest freezes the policy, address, exact source commit, blueprint
digest, and unspent reference-script output. Consumers reject drift from the
policy and address above.

## Stranger journey: find, verify, and dial

Start in a clean directory on any Nix machine. The repository and Cardano
chain are the only inputs:

```console
$ export CKERI_REF=main
$ git clone --filter=blob:none https://github.com/lambdasistemi/cardano-keri
$ cd cardano-keri
$ git checkout "$CKERI_REF"
$ nix shell nixpkgs#nix -c nix run --accept-flake-config --quiet \
    ./offchain#ckeri -- board list \
    --board-manifest deploy/preprod/board-manifest.json
board records: 3
B... verified https https://witness-1.preprod.plutimus.com/ tx <txid>#<index> deposit 4000000
B... verified https https://witness-2.preprod.plutimus.com/ tx <txid>#<index> deposit 4000000
B... verified https https://witness-3.preprod.plutimus.com/ tx <txid>#<index> deposit 4000000
```

Use `main` for a released story. During public PR acceptance, set `CKERI_REF`
to the exact public commit or branch named by that PR; no private artifact is
required.

The outer `nix shell` supplies a current Nix client. This keeps the clean-client
journey portable on hosts whose installed Nix predates support for the
repository's locked sibling `onchain` source. On Nix 2.31 or newer, you may run
the inner `nix run` command directly. `--accept-flake-config` enables the public
IOG cache declared by the project.

`verified` is not a server claim. It means the client:

1. queried the exact current UTxO set at the frozen address;
2. required exactly one amount-1 marker under the frozen policy;
3. bound its raw 32-byte asset name to the datum's witness key;
4. decoded the frozen datum including its Cardano lifecycle owner;
5. verified the KERI 1.0 JSON size, `/loc/scheme` route, SAID, scheme and URL;
   and
6. verified the witness's Ed25519 signature over the exact endpoint bytes.

An invalid output fails the complete catalog read and names its out-ref; the
client never returns a partial trusted-looking list. An optional
`KOIOS_TOKEN` environment variable supplies Koios bearer authorization.
Anonymous reads remain supported.

Dial the witness through its public KERI OOBI route. The catalog gives both
the witness AID and base URL, so no private path is needed:

```console
$ aid=BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI
$ endpoint=https://witness-1.preprod.plutimus.com/
$ curl --fail --silent --show-error \
    --output /dev/null \
    --write-out 'HTTP %{http_code} bytes %{size_download}\n' \
    "${endpoint}oobi/${aid}/controller"
HTTP 200 bytes 1239
```

The base URL is a KERI service endpoint, not a web home page; a generic
`GET /` may correctly return method-not-allowed. The OOBI route above is the
protocol-level dial.

## Witness operator journey: post

Fetch the witness's live controller OOBI response as binary data. Do not copy
and paste CESR through a text editor:

```console
$ curl --fail --silent --show-error \
    --output witness-1-oobi.cesr \
    https://witness-1.preprod.plutimus.com/oobi/B.../controller
$ export CKERI_PAYER=/home/operator/.secrets/cardano-keri-preprod/payment.skey
$ export CKERI_NODE_SOCKET=/code/cardano-preprod/ipc/node.socket
$ export CKERI_FUNDING_ADDRESS=addr_test1...
$ export CKERI_CHANGE_ADDRESS="$CKERI_FUNDING_ADDRESS"
$ nix run --quiet ./offchain#ckeri -- board post \
    --network preprod \
    --network-magic 1 \
    --endpoint-record witness-1-oobi.cesr \
    --board-manifest deploy/preprod/board-manifest.json
board txid: <settled-txid> deposit: 4 tADA
```

The marker asset name is the witness's raw Ed25519 key. The inline datum wraps
the exact endpoint reply, its signature, and the 28-byte Cardano payment-key
hash that controls its lifecycle. Posting mints exactly one marker, and the
policy verifies the witness signature before minting.

All configuration uses `opt-env-conf`: command options, environment variables,
and YAML are equivalent. `optparse-applicative` is not used. Secrets are read
from environment-selected files and are never placed in the manifest or
printed.

The payer key must derive the payment credential in the funding address.
Board mutations enumerate exact candidate out-refs through Koios, resolve
those inputs through N2C, construct and sign in process, and use local
transaction submission. Funding may span several spend inputs; collateral is
kept separate.

## Update

An update spends and recreates the selected record with the same marker and
complete deposit. The recorded Cardano owner must sign:

```console
$ nix run --quiet ./offchain#ckeri -- board update \
    --endpoint-record witness-1-replacement-oobi.cesr \
    --board-manifest deploy/preprod/board-manifest.json
board update txid: <settled-replacement-txid>
replaced: <old-txid>#<old-index>
```

Global uniqueness is intentionally not an on-chain rule. If the same witness
has multiple live records, all remain visible and update refuses ambiguity.
Pass `--board-out-ref TXID#INDEX` to select one explicitly.

## Retire and refund

Retirement spends the selected board output, burns exactly one marker, and
refunds the complete deposit to `--to`. Fee change must use a different
address when the funding address is also the refund target:

```console
$ export CKERI_CHANGE_ADDRESS=addr_test1change...
$ nix run --quiet ./offchain#ckeri -- board retire \
    --witness B... \
    --to addr_test1refund... \
    --board-manifest deploy/preprod/board-manifest.json
board retire txid: <settled-retire-txid>
refunded: 4 tADA to addr_test1refund...
```

After settlement, the spent predecessor is stale and disappears from
`board list`. There is no TTL or wall-clock rule: current means unspent.

## Checkpoint watchability

Checkpoint datums say *who* the controller chose; the endpoint board says
*where* those witnesses currently advertise service. `ckeri status` joins the
two verified sets:

```console
$ nix run --quiet ./offchain#ckeri -- status E... \
    --manifest deploy/preprod/m1-manifest.json \
    --board-manifest deploy/preprod/board-manifest.json
state ACTIVE ... witnesses 3 (toad 2) ... watchable 3/3
```

Duplicates never increase the numerator. Witnessed registration refuses
missing board entries by default; `--allow-unlisted-witnesses` is an explicit
acknowledgement of reduced public watchability.

## Captured preprod lifecycle

The four `m1-board-*-acceptance.txt` files under `deploy/preprod/` form one
ordered mechanical journey. It starts from the released three-record board,
posts transaction
`21050c77383153f740734881e05c369ae989018b5ad6ddacc9bfcd8f72e7edd0`,
proves a stranger can fetch the 1,239-byte OOBI with HTTP 200, updates through
`8d1885773e0e865a5d2e931f2564927a669e25bce16dd837c2f05d6ef7d8d556`,
and retires through
`bac4cbcb8dd4c27509a677791ebcdd6ae98a517c5fb03ecfd22130d3be34638c`.
The final list is the original three records and the full 4-tADA deposit is
refunded to the configured address.
