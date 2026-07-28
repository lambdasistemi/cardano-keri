# Implementation plan: preprod witness pool (#157)

**Branch**: `story/157-witness-pool` | **Date**: 2026-07-28  
**Spec**: `specs/157-preprod-witness-pool/spec.md`

## Summary

Deploy three independent keripy 1.3.5 witnesses behind the existing
production Traefik proxy. Freeze each randomly generated first-start witness
AID in its own named volume, publish the captured AIDs as HTTPS controller
OOBIs, and prove the pool from an empty standard-`kli` client.

This is one application-infrastructure vertical. It changes no Haskell or
on-chain code. The operator-selected cheap-team policy uses solo
implementation with `gate.sh` and GitHub CI as reviewers.

## Technical context

- **Runtime**: keripy 1.3.5 / Python 3.12.
- **Dependency source**: the repository’s existing pinned
  `offchain/test/keri-fixtures/{pyproject.toml,uv.lock}`.
- **Supervisor**: Docker Compose with `restart: unless-stopped`.
- **Persistence**: one named `.keri` data volume per witness.
- **Ingress**: Traefik `web` network and Let’s Encrypt TLS.
- **Public names**:
  `witness-{1,2,3}.preprod.plutimus.com`.
- **Documentation**: MkDocs Material.
- **Acceptance**: standard `kli` in a fresh container volume.

## Story-shaped surface

```text
deploy/preprod/
├── Dockerfile
├── docker-compose.yaml
├── witness-1.json
├── witness-2.json
├── witness-3.json
└── witnesses.json
scripts/check-preprod-witnesses.sh
.github/workflows/ci.yml
docs/user/preprod-witness-pool.md
mkdocs.yml
specs/157-preprod-witness-pool/
├── spec.md
├── plan.md
└── tasks.md
gate.sh
```

## Vertical slice

### Locked witness image

Build a small runtime image whose virtual environment is resolved with
`uv sync --frozen` from the existing keripy fixture lock. Pin the Python and
`uv` source images by digest, install only the libsodium runtime dependency,
run as an unprivileged user, and expose `kli` as the entry point.

### Declarative services

Define three services from the same image. Each gets:

- a distinct name/alias and named data volume;
- the same internal HTTP/TCP ports in its isolated container;
- a read-only endpoint configuration that advertises its public HTTPS URL;
- a health check against the local HTTP service;
- bounded JSON logs;
- Traefik host routing on the external `web` network; and
- no host-published port or secret.

On first start, `kli witness start` creates a non-transferable witness AID in
the mounted data directory. Subsequent starts load it unchanged.

### Deployment and capture

Copy the exact branch source needed to build under
`~/services/cardano-keri-witnesses/` on `production`, then run
`docker compose up --build -d`. Capture each printed witness AID from the
running service and form
`https://<host>/oobi/<AID>/controller`. Commit those captured values to
`witnesses.json`; never pre-compute or hand-invent them.

Restart only the three new services. Inspect their restart policies, mounts,
health, and post-restart AIDs. Do not reboot the production host or restart
the Docker daemon because unrelated production workloads share it.

### Reproducible acceptance and CI

The acceptance script:

1. validates exact manifest structure and AID/OOBI agreement with `jq`;
2. validates the resolved Compose model;
3. checks the locked image reports keripy 1.3.5;
4. fetches each public OOBI;
5. creates an empty client data volume;
6. runs `kli init`, three `kli oobi resolve` commands, witnessed `kli incept`,
   and `kli status`; and
7. asserts count 3, receipts 3, threshold 2 before removing only its uniquely
   named temporary client volume.

A dedicated CI job builds the image and runs the checked-in verifier.

### User documentation

Add `docs/user/preprod-witness-pool.md` to the User guide navigation. Explain:

- what a KERI witness and OOBI are;
- the published manifest and its raw-main URL;
- the exact clean-client commands and captured successful output;
- the three-on-one-host trust/availability boundary; and
- how operators verify health and restart persistence.

## Verification and delivery

1. Validate Dockerfile/Compose/JSON locally and build the locked image.
2. Deploy the three services and capture their AIDs.
3. Prove public OOBIs before and after service restart.
4. Run the empty-client acceptance and freeze its output.
5. Insert only captured output in the docs page.
6. Run strict MkDocs, link checking, the deployment verifier, and `just ci`
   through `./gate.sh` on the exact staged tree.
7. Review the full diff, check every task, and commit the vertical slice with
   `Tasks: T157`.
8. Push, update the plain-language PR body, and wait for every CI check.
9. Restore the repository’s standing `gate.sh` to its base form in the final
   ready-for-review commit, mark PR #167 ready, and park for operator merge.

## Risk controls

- A witness AID is not published until its persistent volume exists and the
  public OOBI resolves.
- No floating container or package tag enters the deployment.
- The verifier rejects duplicate AIDs, non-HTTPS URLs, AID/path mismatch, and
  anything other than exactly three entries.
- Restart proof compares captured before/after facts and touches only the new
  services.
- The docs do not claim administrative independence or production SLA.
- No future `ckeri` parser is introduced here. Story #158 remains bound to
  `opt-env-conf`; `optparse-applicative` remains forbidden.

