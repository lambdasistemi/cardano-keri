# The preprod witness pool

The project operates three public
[KERI](../keri-primer.md) witnesses for preprod integration. A controller can
resolve their out-of-band introductions (OOBIs), use the three witness AIDs in
an inception event, and collect receipts at a threshold of two.

This pool is integration infrastructure. It is not a production trust service
or a substitute for independently operated witnesses.

## Public witnesses

The repository-owned source of truth is
`deploy/preprod/witnesses.json`. Its stable raw URL after this page lands on
`main` is:

```text
https://raw.githubusercontent.com/lambdasistemi/cardano-keri/main/deploy/preprod/witnesses.json
```

| Witness | AID | Controller OOBI |
| --- | --- | --- |
| `witness-1` | `BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI` | `https://witness-1.preprod.plutimus.com/oobi/BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI/controller` |
| `witness-2` | `BBkK9o9mMm_nIu5yl3x3L7ti8cYoKg-AoxpqQapMcE5B` | `https://witness-2.preprod.plutimus.com/oobi/BBkK9o9mMm_nIu5yl3x3L7ti8cYoKg-AoxpqQapMcE5B/controller` |
| `witness-3` | `BNP31dFWbqS_oUe2CUu24Ct7cQjpk3DscLzbpGT5OEz4` | `https://witness-3.preprod.plutimus.com/oobi/BNP31dFWbqS_oUe2CUu24Ct7cQjpk3DscLzbpGT5OEz4/controller` |

An OOBI is discovery data: it gives a KERI client the witness identity,
controller role authorization, and signed HTTPS location record. The client
still validates the KERI material it receives.

## Reproduce the clean-client proof

The checked-in verifier builds no KERI behavior of its own. It drives standard
keripy 1.3.5 `kli init`, `kli oobi resolve`, `kli incept`, and `kli status`
commands inside a uniquely named empty Docker volume:

```console
$ docker build \
    --tag cardano-keri-witness:acceptance \
    --file deploy/preprod/Dockerfile \
    .
$ WITNESS_IMAGE=cardano-keri-witness:acceptance \
    ./scripts/check-preprod-witnesses.sh
```

The script also checks the manifest shape, the resolved Compose model, the
locked keripy version, and all three public OOBIs. It deletes only the
temporary client volume it created.

This transcript was captured from a clean client on 28 July 2026:

```text
Library version: 1.3.5
reachable: witness-1 BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI
reachable: witness-2 BBkK9o9mMm_nIu5yl3x3L7ti8cYoKg-AoxpqQapMcE5B
reachable: witness-3 BNP31dFWbqS_oUe2CUu24Ct7cQjpk3DscLzbpGT5OEz4
https://witness-1.preprod.plutimus.com/oobi/BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI/controller resolved
https://witness-2.preprod.plutimus.com/oobi/BBkK9o9mMm_nIu5yl3x3L7ti8cYoKg-AoxpqQapMcE5B/controller resolved
https://witness-3.preprod.plutimus.com/oobi/BNP31dFWbqS_oUe2CUu24Ct7cQjpk3DscLzbpGT5OEz4/controller resolved
Waiting for witness receipts...
Prefix  EH_IC5Komc6gaD5okE8e6eCMrqwHZeI0UZHlHX1PbYDn

Alias:  alice
Identifier: EH_IC5Komc6gaD5okE8e6eCMrqwHZeI0UZHlHX1PbYDn
Seq No: 0

Witnesses:
Count:          3
Receipts:       3
Threshold:      2

PASS: clean kli client received 3 of 3 witness receipts at threshold 2
```

The generated controller AID and keys differ on every clean run. The stable
acceptance facts are the three configured witnesses, three receipts, and
threshold two.

## Deployment shape

`deploy/preprod/docker-compose.yaml` defines three isolated keripy processes.
They share the same dependency-locked image but have separate containers and
named data volumes. The public hosts terminate TLS through Traefik; no witness
port is published directly on the Docker host.

Each service has:

- `restart: unless-stopped`;
- a local HTTP health check;
- a distinct persistent `.keri` volume;
- bounded Docker JSON logs;
- a read-only root filesystem, dropped Linux capabilities, and
  `no-new-privileges`; and
- an unprivileged numeric user.

The endpoint JSON contains no secret. At startup it is copied from its
read-only image input to keripy's writable configuration path in the
persistent volume, then `kli witness start` takes over. The witness keys and
databases remain only in that service's volume.

The production capture used NixOS 26.05 on `x86_64`, Docker 29.2.1, Docker
Compose 5.0.2, and keripy 1.3.5. All three containers reported healthy after a
simultaneous service restart, and the three AIDs above remained byte-for-byte
unchanged.

## Operator checks

From `deploy/preprod`, resolve and inspect the deployment:

```console
$ docker compose config --quiet
$ docker compose ps
$ jq -r '.[] | [.name, .aid, .oobi] | @tsv' witnesses.json
$ ../../scripts/check-preprod-witnesses.sh
```

To prove persistence without disturbing unrelated workloads, record the
manifest, restart only these services, wait for all health checks, and rerun
the verifier:

```console
$ docker compose restart witness-1 witness-2 witness-3
$ docker compose ps
$ ../../scripts/check-preprod-witnesses.sh
```

Do not delete or replace a witness data volume after publishing its AID.
Starting the service with an empty replacement volume creates a different
witness identity, which requires a coordinated manifest and consumer update.

## Trust and availability boundary

!!! warning "One administrative and failure domain"
    All three witnesses currently run on one host under one operator. A
    two-of-three receipt threshold therefore proves KERI protocol behavior
    and integration reachability, but it does not provide two independent
    operators. One host outage can make the entire pool unavailable, and a
    compromised host administrator can compromise all three witnesses.

The endpoints are public and unauthenticated so preprod clients can resolve
OOBIs and request receipts. They carry no production service-level objective,
durability promise, DDoS guarantee, or mainnet endorsement. Consumers should
expect maintenance interruptions and must not treat the pool as an
independently governed trust quorum.
