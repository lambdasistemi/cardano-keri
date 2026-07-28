# Feature specification: preprod witness pool (#157)

**Feature branch**: `story/157-witness-pool`  
**Created**: 2026-07-28  
**Status**: Approved for implementation  
**Issue**: https://github.com/lambdasistemi/cardano-keri/issues/157  
**Parent**: producer applications epic #156, milestone M1

## User scenarios

### User Story 1 — Discover the public pool (P1)

A stranger reads one repository-owned JSON document and learns the three
preprod witness AIDs and their public out-of-band introduction (OOBI) URLs.
Every URL is reachable over HTTPS without credentials.

**Independent proof**: validate the checked-out JSON, fetch all three OOBIs
from a public network boundary, and confirm each response identifies the AID
embedded in its URL.

### User Story 2 — Incept a witnessed identity with standard `kli` (P1)

A controller starts from an empty keripy 1.3.5 client, resolves the three
published OOBIs, and incepts a transferable identity with witness threshold
two. Standard `kli status` reports all three witness receipts.

**Independent proof**: a clean client reports witness count 3, receipt count
3, and threshold 2 without any private service configuration.

### User Story 3 — Witness identities survive service restart (P1)

Infrastructure replacement does not silently change the public witness AIDs.
Each service has its own persistent database/key volume and starts
automatically after the Docker daemon returns.

**Independent proof**: capture the three running AIDs, inspect the declared
restart policy and mounts, restart only the three witness containers, and
observe byte-identical AIDs and reachable OOBIs afterward.

### User Story 4 — Operate the pool from repository state (P1)

An operator can build and launch the pool from the committed deployment
definition. Keripy and all Python dependencies are locked; the services have
health checks, bounded logs, TLS routing, and no committed secrets.

## Functional requirements

- **FR-001**: The deployment MUST run exactly three independent keripy 1.3.5
  witness services.
- **FR-002**: Each service MUST use a distinct persistent data volume and
  `restart: unless-stopped`.
- **FR-003**: The services MUST expose their HTTP APIs at
  `witness-{1,2,3}.preprod.plutimus.com` through Traefik TLS.
- **FR-004**: Each witness configuration MUST advertise its own stable public
  HTTPS controller location. Direct public TCP exposure is not required.
- **FR-005**: The keripy image MUST build from the repository’s committed
  dependency lock. Floating `latest` tags are forbidden.
- **FR-006**: `deploy/preprod/witnesses.json` MUST contain exactly three
  entries. Each entry MUST have a unique name and AID plus an HTTPS controller
  OOBI whose path contains that same AID.
- **FR-007**: Every published OOBI MUST resolve from the public internet
  without authentication.
- **FR-008**: A clean standard-`kli` client MUST resolve all three OOBIs and
  incept a transferable 1-of-1 identity with the published witnesses and
  `toad=2`.
- **FR-009**: The resulting `kli status` MUST report witness count 3, receipt
  count 3, and threshold 2.
- **FR-010**: The repository MUST provide a reproducible validation command
  that checks JSON/Compose invariants, the keripy version, public OOBIs, and
  the clean-client inception.
- **FR-011**: GitHub CI MUST run the deployment validation from the checked-out
  branch and fail on drift.
- **FR-012**: The same PR MUST add a navigable MkDocs page titled “The preprod
  witness pool,” with the captured successful CLI transcript and operational
  boundaries.
- **FR-013**: Machine facts in JSON, docs, and PR evidence MUST come from
  captured command output; witness AIDs and acceptance values are never
  retyped from memory.
- **FR-014**: The existing Haskell, Aiken, Lean, and documentation gates MUST
  remain green.

## Key entities

- **Witness AID**: a non-transferable KERI identifier whose key is held in one
  service’s persistent volume.
- **Controller OOBI**: the public URL from which `kli` learns a witness AID and
  its service endpoint.
- **TOAD**: KERI’s threshold of accountable duplicity; the pool’s acceptance
  identity uses 2 of 3.
- **Pool manifest**: `deploy/preprod/witnesses.json`, the repository source of
  truth consumed by controllers and later producer applications.

## Success criteria

- **SC-001**: Three public HTTPS OOBIs resolve and expose three distinct AIDs.
- **SC-002**: A clean keripy 1.3.5 client collects three inception receipts at
  threshold two.
- **SC-003**: Restarting all three witness containers preserves every AID and
  restores healthy public endpoints.
- **SC-004**: The locked image identifies itself as keripy 1.3.5.
- **SC-005**: Strict MkDocs, link checking, deployment validation, and the full
  repository `just ci` gate exit zero.
- **SC-006**: GitHub CI is green and the PR is parked, mergeable, for operator
  review.

## Assumptions and boundaries

- `kli` owns all KERI-side actions. This story does not wrap inception,
  rotation, receipt, or status commands.
- The pool is preprod infrastructure, not a promise of production SLA or
  independent administrative trust: all three services initially share one
  host and operator.
- Host-restart survivability is proved without rebooting unrelated production
  workloads: named volumes plus the restart policy are inspected, and the
  three new containers are restarted end to end.
- There are no Cardano transactions in this story, so the epic’s generic
  settled-preprod-txid evidence is not applicable.
- During PR CI, validation reads the checked-out manifest. The raw GitHub
  `main` URL becomes authoritative after operator merge.

