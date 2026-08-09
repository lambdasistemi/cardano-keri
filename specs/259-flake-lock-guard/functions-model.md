# Functions model — #259 flake-lock enforcement

Artifact ceiling: 3,000 bytes and 90 lines.

Only new or changed command surfaces are modeled. There is no Haskell or Aiken
API change.

## Guard command

- **FUN-259-GUARD:** `check-flake-lock-guard repositoryRoot -> ExitStatus`

Constraints:

- reads the authoritative sources named by **EDGE-259-03**;
- returns success only for **DATA-INV-259-01**, complete no-write coverage,
  and both caller edges;
- emits **DAT-259-GUARD-REPORT** counts on success;
- accepts no update/write mode and never repairs the lock.

## Root gate command

- **FUN-259-CI:** `just ci -> ExitStatus`

Constraints:

- reaches **FUN-259-GUARD**;
- runs all existing onchain, BLAKE3, and offchain CI dependencies;
- after dependencies complete, fails if `offchain/flake.lock` differs from the
  committed tree.

## Workflow command surface

- **FUN-259-WORKFLOW:** `github-ci-flake-lock-guard checkout -> ExitStatus`

Constraints:

- reaches **FUN-259-GUARD** in a required `.github/workflows/ci.yml` step;
- every direct command evaluating the primary offchain flake passes no-write;
- non-evaluation or guard failure fails the job.
