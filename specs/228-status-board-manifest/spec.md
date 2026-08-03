# Story 228: status fails outside a source checkout over the board manifest

**Created**: 2026-08-03
**Status**: Draft
**Input**: ckeri 0.2.0 funded-lifecycle experiment on preprod (feedback F4).

## Outcome

`ckeri status AID` works from a release artifact plus downloaded manifests,
without a cardano-keri checkout on disk.

## Observed behavior (0.2.0)

```
$ ckeri status EJ5lJ-… --manifest m1-manifest.json
deploy/preprod/board-manifest.json: withBinaryFile: does not exist (No such file or directory)
```

The board manifest is only needed for the `watchable n/m` enrichment, but
its absence aborts the whole status report with a raw IO error.

## Root cause (verified in sources)

- `offchain/cli/Cardano/KERI/CLI/Backend.hs:512` — default
  `"deploy/preprod/board-manifest.json"` for `--board-manifest`.
- Same default repeated for other verbs in
  `offchain/deployment/Cardano/KERI/Deployment/CLI.hs:532,838,875,944`.
- The path is relative to the working directory and only resolves inside a
  repository checkout; the release artifacts do not include the manifests
  (they live in `deploy/preprod/` in the repo).

## Acceptance scenarios

1. **Given** only the release binary and a downloaded m1 manifest, **When**
   `ckeri status AID --manifest m1-manifest.json` runs, **Then** it prints
   the checkpoint report, omitting the `watchable` field (or printing
   `watchable unavailable`) instead of failing.
2. **Given** the same setup with `--board-manifest` supplied, **When**
   status runs, **Then** the full report including `watchable n/m` is
   printed, exactly as today.
3. **Given** a missing manifest path, **When** any verb reads it, **Then**
   the error is a one-line message naming the file and its purpose, not a
   `withBinaryFile` IO trace (see Story 231).

## Suggested directions

- Treat `--board-manifest` as optional in `status` (degrade gracefully).
- Publish `m1-manifest.json` and `board-manifest.json` as release assets so
  the documented install path has canonical manifest URLs.

## Out of scope

- Board semantics themselves (Story 165 territory).
